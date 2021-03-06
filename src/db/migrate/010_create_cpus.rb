class CreateCpus < ActiveRecord::Migration
  def self.up
    create_table :cpus do |t|
        t.integer :host_id
        t.foreign_key :hosts, :name => 'fk_host_cpus'
        t.integer :cpu_number
        t.integer :core_number
        t.integer :number_of_cores
        t.string  :vendor, :limit => 128
        t.integer :model
        t.integer :family
        t.integer :cpuid_level
        t.float   :speed
        t.string  :cache
        t.string  :flags

        t.timestamps
    end

    remove_column :hosts, :cpu_speed
    remove_column :hosts, :num_cpus
  end

  def self.down
    drop_table :cpus

    add_column :hosts, :cpu_speed, :integer
    add_column :hosts, :num_cpus,  :integer
  end
end
