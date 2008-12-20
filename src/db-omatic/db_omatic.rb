#!/usr/bin/ruby

$: << File.join(File.dirname(__FILE__), "../dutils")

require "rubygems"
require "qpid"
require 'monitor'
require 'dutils'
require 'daemons'
require 'optparse'
include Daemonize


class DbOmatic < Qpid::Qmf::Console

    # Use monitor mixin for mutual exclusion around checks to heartbeats
    # and updates to objects/heartbeats.

    include MonitorMixin

    def initialize()
        super()
        @cached_objects = {}
        @heartbeats = {}

        database_connect
    end

    def log(s)
        puts "#{Time.now}: #{s}"
    end

    def update_domain_state(domain, state_override = nil)
        vm = Vm.find(:first, :conditions => [ "uuid = ?", domain['uuid'] ])
        if vm == nil
            log "VM Not found in database, must be created by user; ignoring."

            #XXX: I mark this one as 'synced' here even though we couldn't sync
            #it because there really should be a db entry for every vm unless it
            #was created outside of ovirt.
            domain[:synced] = true
            return
        end

        if state_override != nil
            state = state_override
        else
            # FIXME: Some of these translations don't seem right.  Shouldn't we be using
            # the libvirt states throughout ovirt?
            case domain['state']
                when "nostate"
                    state = Vm::STATE_PENDING
                when "running"
                    state = Vm::STATE_RUNNING
                when "blocked"
                    state = Vm::STATE_SUSPENDED #?
                when "paused"
                    state = Vm::STATE_SUSPENDED
                when "shutdown"
                    state = Vm::STATE_STOPPED
                when "shutoff"
                    state = Vm::STATE_STOPPED
                when "crashed"
                    state = Vm::STATE_STOPPED
                else
                    state = Vm::STATE_PENDING
            end
        end

        log "Updating VM #{domain['name']} to state #{state}"
        vm.state = state
        vm.save

        domain[:synced] = true
    end

    def update_host_state(host_info, state)
        db_host = Host.find(:first, :conditions => [ "hostname = ?", host_info['hostname'] ])
        if db_host
            log "Marking host #{host_info['hostname']} as state #{state}."
            db_host.state = state
            db_host.hypervisor_type = host_info['hypervisorType']
            db_host.arch = host_info['model']
            db_host.memory = host_info['memory']
            # XXX: Could be added..
            #db_host.mhz = host_info['mhz']
            # XXX: Not even sure what this is.. :)
            #db_host.lock_version = 2
            # XXX: This would just be for init..
            #db_host.is_disabled = 0
            db_host.save
            host_info[:synced] = true
        else
            # FIXME: This would be a newly registered host.  We could put it in the database.
            log "Unknown host, probably not registered yet??"
            # XXX: So it turns out this can happen as there is a race condition on bootup
            # where the registration takes longer than libvirt-qpid does to relay information.
            # So in this case, we mark this object as not synced so it will get resynced
            # again in the heartbeat.
            host_info[:synced] = false
        end
    end

    def object_props(broker, obj)
        target = obj.klass_key[0]
        return if target != "com.redhat.libvirt"

        type = obj.klass_key[1]

        # I just sync this whole thing because there shouldn't be a lot of contention here..
        synchronize do
            values = @cached_objects[obj.object_id.to_s]

            new_object = false

            if values == nil
                values = {}
                @cached_objects[obj.object_id.to_s] = values

                # Save the agent and broker bank so that we can tell what objects
                # are expired when the heartbeat for them stops.
                values[:broker_bank] = obj.object_id.broker_bank
                values[:agent_bank] = obj.object_id.agent_bank
                values[:class_type] = obj.klass_key[1]
                values[:timed_out] = false
                values[:synced] = false
                log "New object type #{type}"

                new_object = true
            end

            domain_state_change = false

            obj.properties.each do |key, newval|
                if values[key.to_s] != newval
                    values[key.to_s] = newval
                    #log "new value for property #{key} : #{newval}"
                    if type == "domain" and key.to_s == "state"
                        domain_state_change = true
                    end
                end
            end

            if domain_state_change
                update_domain_state(values)
            end

            if new_object
                if type == "node"
                    update_host_state(values, Host::STATE_AVAILABLE)
                end
            end
        end
    end

    def object_stats(broker, obj)
        target = obj.klass_key[0]
        return if target != "com.redhat.libvirt"
        type = obj.klass_key[1]

        synchronize do
            values = @cached_objects[obj.object_id.to_s]
            if !values
                values = {}
                @cached_objects[obj.object_id.to_s] = values

                values[:broker_bank] = obj.object_id.broker_bank
                values[:agent_bank] = obj.object_id.agent_bank
                values[:class_type] = obj.klass_key[1]
                values[:timed_out] = false
                values[:synced] = false
            end
            obj.statistics.each do |key, newval|
                if values[key.to_s] != newval
                    values[key.to_s] = newval
                    #log "new value for statistic #{key} : #{newval}"
                end
            end
        end
    end

    def heartbeat(agent, timestamp)
        return if agent == nil
        synchronize do
            bank_key = "#{agent.agent_bank}.#{agent.broker.broker_bank}"
            @heartbeats[bank_key] = [agent, timestamp]
        end
    end


    def del_agent(agent)
        agent_disconnected(agent)
    end

    # This method marks objects associated with the given agent as timed out/invalid.  Called either
    # when the agent heartbeats out, or we get a del_agent callback.
    def agent_disconnected(agent)
        @cached_objects.keys.each do |objkey|
            if @cached_objects[objkey][:broker_bank] == agent.broker.broker_bank and
               @cached_objects[objkey][:agent_bank] == agent.agent_bank

                values = @cached_objects[objkey]
                log "Marking object of type #{values[:class_type]} as timed out."
                if values[:timed_out] == false
                    if values[:class_type] == 'node'
                        update_host_state(values, Host::STATE_UNAVAILABLE)
                    elsif values[:class_type] == 'domain'
                        update_domain_state(values, Vm::STATE_UNREACHABLE)
                    end
                end
            values[:timed_out] = true
            end
        end
    end

    # The opposite of above, this is called when an agent is alive and well and makes sure
    # all of the objects associated with it are marked as valid.
    def agent_connected(agent)

        @cached_objects.keys.each do |objkey|
            if @cached_objects[objkey][:broker_bank] == agent.broker.broker_bank and
               @cached_objects[objkey][:agent_bank] == agent.agent_bank

                values = @cached_objects[objkey]
                if values[:timed_out] == true or values[:synced] == false
                    log "Marking object of type #{values[:class_type]} as in service."
                    if values[:class_type] == 'node'
                        update_host_state(values, Host::STATE_AVAILABLE)
                    elsif values[:class_type] == 'domain'
                        update_domain_state(values)
                    end
                    values[:timed_out] = false
                end
            end
        end
    end

    # This cleans up the database on startup so that everything is marked unavailable etc.
    # Once everything comes online it will all be marked as available/up again.
    def db_init_cleanup()
        db_host = Host.find(:all)
        db_host.each do |host|
            log "Marking host #{host.hostname} unavailable"
            host.state = Host::STATE_UNAVAILABLE
            host.save
        end

        db_vm = Vm.find(:all)
        db_vm.each do |vm|
            log "Marking vm #{vm.description} as stopped."
            vm.state = Vm::STATE_STOPPED
            vm.save
        end
    end


    # This is the mainloop that is called into as a separate thread.  This just loops through
    # and makes sure all the agents are still reporting.  If they aren't they get marked as
    # down.
    def check_heartbeats()
        while true
            sleep(5)

            synchronize do
                # Get seconds from the epoch
                t = Time.new.to_i

                @heartbeats.keys.each do | key |
                    agent, timestamp = @heartbeats[key]

                    # Heartbeats from qpid are in microseconds, we just need seconds..
                    s = timestamp / 1000000000
                    delta = t - s

                    if delta > 30
                        # No heartbeat for 30 seconds.. deal with dead/disconnected agent.
                        agent_disconnected(agent)

                        @heartbeats.delete(key)
                    else
                        agent_connected(agent)
                    end
                end
            end
        end
    end
end


$logfile = '/var/log/ovirt-server/db-omatic.log'

def main()

    do_daemon = true

    opts = OptionParser.new do |opts|
        opts.on("-h", "--help", "Print help message") do
            puts opts
            exit
        end
        opts.on("-n", "--nodaemon", "Run interactively (useful for debugging)") do |n|
            do_daemon = false
        end
    end
    begin
        opts.parse!(ARGV)
    rescue OptionParser::InvalidOption
        puts opts
        exit
    end

    if do_daemon
        # XXX: This gets around a problem with paths for the database stuff.
        # Normally daemonize would chdir to / but the paths for the database
        # stuff are relative so it breaks it.. It's either this or rearrange
        # things so the db stuff is included after daemonizing.
        pwd = Dir.pwd
        daemonize
        Dir.chdir(pwd)

        lf = open($logfile, 'a')
        $stdout = lf
        $stderr = lf
        puts "#{Time.now}: db_omatic started."
    end

    dbsync = DbOmatic.new()
    s = Qpid::Qmf::Session.new(:console => dbsync, :rcv_events => false)
    b = s.add_broker("amqp://localhost:5672")

    dbsync.db_init_cleanup()

    # Call into mainloop..
    dbsync.check_heartbeats()
end

main()
