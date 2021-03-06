#
# Copyright (C) 2009 Red Hat, Inc.
# Written by Scott Seago <sseago@redhat.com>,
#            David Lutterkort <lutter@redhat.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301, USA.  A copy of the GNU General Public License is
# also available at http://www.gnu.org/copyleft/gpl.html.
# Mid-level API: Business logic around HW pools
module HardwarePoolService

  include PoolService

  # Load a new HardwarePool for creating
  #
  # === Instance variables
  # [<tt>@pool</tt>] loads a new HardwarePool object into memory
  # [<tt>@parent</tt>] stores the parent of <tt>@pool</tt> as specified by
  #                    +parent_id+
  # === Required permissions
  # [<tt>Privilege::MODIFY</tt>] for the parent pool
  def svc_new(parent_id, attributes=nil)
    @pool = HardwarePool.new(attributes)
    pool_new(parent_id)
  end

  # Save a new HardwarePool
  #
  # === Instance variables
  # [<tt>@pool</tt>] the newly saved HardwarePool
  # [<tt>@parent</tt>] stores the parent of <tt>@pool</tt> as specified by
  #                    +parent_id+
  # === Required permissions
  # [<tt>Privilege::MODIFY</tt>] for the parent pool
  def svc_create(pool_hash, parent_id, other_args)
    svc_new(parent_id, pool_hash)

    Pool.transaction do
      @pool.create_with_parent(@parent)
      begin
        if other_args[:resource_type]
          svc_move_items_internal(@pool.id, other_args[:resource_type],
                                  other_args[:resource_ids].split(","),
                                  @pool.id)
        end
      # wrapped in a transaction, so fail on partial success
      rescue PartialSuccessError => ex
        # Raising ActionError here since we're aborting the transaction. Errors
        # on creation here result in no persistent changes to the database.
        raise ActionError.new("Could not move all hosts or storage to this pool")
      end
    end
    return "Hardware Pool was successfully created."
  end

  # Move Hosts identified by +host_ids+ from one Hardware Pool to another. The
  # target pool for the hosts is specified as +target_pool_id+.
  #
  # === Instance variables
  # [<tt>@pool</tt>] the current HardwarePool
  # [<tt>@parent</tt>] the parent of <tt>@pool</tt>
  # === Required permissions
  # [<tt>Privilege::MODIFY</tt>] for the target pool as well as the current
  #                              pool for each moved host
  def svc_move_hosts(pool_id, host_ids, target_pool_id)
    svc_move_items_internal(pool_id, Host, host_ids, target_pool_id)
  end

  # Move Storage Pools identified by +storage_pool_ids+ from one Hardware Pool
  # to another. The target pool for the hosts is specified as +target_pool_id+.
  #
  # === Instance variables
  # [<tt>@pool</tt>] the current HardwarePool
  # [<tt>@parent</tt>] the parent of <tt>@pool</tt>
  # === Required permissions
  # [<tt>Privilege::MODIFY</tt>] for the target pool as well as the current
  #                              pool for each moved Storage Pool
  def svc_move_storage(pool_id, storage_pool_ids, target_pool_id)
    svc_move_items_internal(pool_id, StoragePool, storage_pool_ids, target_pool_id)
  end
  def svc_move_items_internal(pool_id, item_class, resource_ids, target_pool_id)
    target_pool = Pool.find(target_pool_id)
    authorized!(Privilege::MODIFY,target_pool)
    lookup(pool_id, Privilege::MODIFY)

    resources = item_class.find(resource_ids)

    # relay error message if movable check fails for any resource
    success = true
    failed_resources = {}
    successful_resources = []
    resources.each do |resource|
      begin
        if !resource.movable?
          failed_resources[resource] = resource.not_movable_reason
        elsif ! resource.hardware_pool.can_modify(@user)
          failed_resources[resource] = "Failed permission check"
        else
          resource.hardware_pool = target_pool
          resource.save!
          successful_resources << resource
        end
      rescue Exception => ex
        failed_resources[resource] = ex.message
      end
    end
    unless failed_resources.empty?
      raise PartialSuccessError.new("Move failed for some " +
                                    "#{item_class.table_name.humanize}",
                                    failed_resources, successful_resources)
    end
    return "Move #{item_class.table_name.humanize} successful."
  end

  def additional_update_actions(pool, pool_hash)
    # FIXME: For the REST API, we allow moving hosts/storage through
    # update.  It makes that operation convenient for clients, though makes
    # the implementation here somewhat ugly.
    begin
      [:hosts, :storage_pools].each do |k|
        objs = pool_hash.delete(k)
        ids = objs.reject{ |obj| obj[:hardware_pool_id] == @pool.id}.
          collect{ |obj| obj[:id] }
        if ids.size > 0
          if k == :hosts
            svc_move_hosts(pool.id, ids, pool.id)
          else
            svc_move_storage(pool.id, ids, pool.id)
          end
        end
      end
      # wrapped in a transaction, so fail on partial success
    rescue PartialSuccessError => ex
      raise ActionError.new("Could not move all hosts or storage to this pool")
    end
  end

  def check_destroy_preconditions
    msg = nil
    if @pool == HardwarePool.get_default_pool
      msg = "You can't delete the top level Hardware pool"
    elsif not(@pool.children.empty?)
      msg = "You can't delete a Pool without first deleting its children."
    elsif not(@pool.hosts.empty?)
      msg = "You can't delete a Pool without first moving its hosts."
    elsif not(@pool.storage_pools.empty?)
      msg = "You can't delete a Pool without first moving its storage."
    end
    raise ActionError.new(msg) if msg
  end
end
