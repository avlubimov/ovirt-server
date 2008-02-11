class CreateVms < ActiveRecord::Migration
  def self.up
    create_table :vms do |t|
      t.column :uuid,                :string
      t.column :description,         :string
      t.column :num_vcpus_allocated, :integer
      t.column :num_vcpus_used,      :integer
      t.column :memory_allocated,    :integer
      t.column :memory_used,         :integer
      t.column :vnic_mac_addr,       :string
      t.column :state,               :string
      t.column :host_id,             :integer
      t.column :vm_library_id,       :integer
      t.column :needs_restart,       :integer
      t.column :boot_device,         :string, :null => false
    end
    execute "alter table vms add constraint fk_vms_hosts
             foreign key (host_id) references hosts(id)"
    execute "alter table vms add constraint fk_vms_vm_libraries
             foreign key (vm_library_id) references vm_libraries(id)"

    create_table :storage_volumes_vms, :id => false do |t|
      t.column :vm_id,             :integer, :null => false
      t.column :storage_volume_id, :integer, :null => false
    end
    execute "alter table storage_volumes_vms add constraint fk_stor_vol_vms_vm_id
             foreign key (vm_id) references vms(id)"
    execute "alter table storage_volumes_vms add constraint fk_stor_vol_vms_stor_vol_id
             foreign key (storage_volume_id) references storage_volumes(id)"
  end

  def self.down
    drop_table :storage_volumes_vms
    drop_table :vms
  end
end