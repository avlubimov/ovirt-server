#--
#  Copyright (C) 2008 Red Hat Inc.
#
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public
#  License as published by the Free Software Foundation; either
#  version 2.1 of the License, or (at your option) any later version.
#
#  This library is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public
#  License along with this library; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA
#
# Author: Joey Boggs <jboggs@redhat.com>
#--

import "appliance_base"
#import "firewall"


define apache_htdigest($digest_file, $digest_username, $digest_password, $digest_realm="")
{
        file_append{"add_htdigest_for_$digest_username_in_$digest_realm":
                                file    => $digest_file,
                                line    => template("ovirt/digest_line.erb")
        }

}


define cobbler_user_config($cobbler_user_name="",$cobbler_user_password="",$cobbler_hostname="") {

	file_replacement{"cobbler_user_name_config":
	        file => "/usr/share/ovirt-server/config/cobbler.yml",
	        pattern => "^username.*$",
	        replacement => "username: $cobbler_user_name",
		require => Package[ovirt-server]
        }

	file_replacement{"cobbler_user_password_config":
		file => "/usr/share/ovirt-server/config/cobbler.yml",
		pattern => "^password.*$",
	        replacement => "password: $cobbler_user_password",
		require => File_replacement[cobbler_user_name_config]
        }
        file_replacement{"cobbler_hostname_config":
                file => "/usr/share/ovirt-server/config/cobbler.yml",
                pattern => "^hostname.*$",
                replacement => "hostname: $cobbler_hostname",
		require => File_replacement[cobbler_user_name_config]
        }

}

class cobbler::bundled {
	package {"cobbler":
		ensure => installed
	}

        package {"ovirt-node-image-pxe":
                ensure => installed
        }

	apache_htdigest{"cobbler_add_user":
	        digest_file => "/etc/cobbler/users.digest",
	        digest_username => "$cobbler_user_name",
	        digest_password => "$cobbler_user_password",
	        digest_realm => "Cobbler",
		require => Package[cobbler]
	}

        cobbler_user_config {"cobbler_bundled_user":
                cobbler_user_name=> "$cobbler_user_name",
                cobbler_user_password => "$cobbler_user_password",
                cobbler_hostname => "localhost",
		require => Package[cobbler]
        }

	file_replacement{"settings_ip_address":
		file => "/etc/cobbler/settings",
		pattern	=> "127.0.0.1",
		replacement => $ipaddress,
		notify => Service[cobblerd],
		require => Package[cobbler]
	}

	file_replacement{"settings_xml_rpc":
		file => "/etc/cobbler/settings",
		pattern	=> "xmlrpc_rw_enabled: 0",
		replacement => "xmlrpc_rw_enabled: 1",
		require => File_replacement[settings_ip_address],
		notify=> Service[cobblerd]
        }

	service {"cobblerd" :
		ensure => running,
		enable => true,
		require => File_replacement[settings_ip_address]
	}

    file {"/etc/cobbler/modules.conf":
        source => "puppet:///ovirt/modules.conf",
        notify	 	=> Service[cobblerd],
        require => Package["cobbler"]
    }

	firewall_rule{"25150": destination_port => "25150"}
	firewall_rule{"25151": destination_port => "25151"}

      file {"/usr/sbin/cobbler-import":
              source => "puppet:///ovirt/cobbler-import",
              mode => 755
      }

    single_exec {"cobbler-import":
        command => "/usr/sbin/cobbler-import >> /var/log/cobbler-import.log 2>&1",
        require => [File["/usr/sbin/cobbler-import"],
                   Service["cobblerd"],Package[ovirt-node-image-pxe],Package[livecd-tools]]
    }
        file_replacement{"settings_auth_module":
                file => "/etc/cobbler/settings",
                pattern => "module = authn_denyall",
                replacement => "module = authn_configfile",
                require => Package[cobbler],
                notify => Service[cobblerd]
        }

        file_replacement{"settings_server":
                file => "/etc/cobbler/settings",
                pattern => "server: 127.0.0.1",
                replacement => "server: $guest_ipaddr",
                require => Package[cobbler],
                notify => Service[cobblerd]
        }

        file_replacement{"settings_next_server":
                file => "/etc/cobbler/settings",
                pattern => "next_server: 127.0.0.1",
                replacement => "next_server: $guest_ipaddr",
                require => Package[cobbler],
                notify => Service[cobblerd]
        }

}

class cobbler::remote {

#    On the remote cobbler server run the following command:
#    htdigest /etc/cobbler/users.digest "Cobbler" $user_name
#    Ensure the password is set to $cobbler_user_password


        cobbler_user_config {"cobbler_remote_user":
                cobbler_user_name => "$cobbler_user_name",
                cobbler_user_password => "$cobbler_user_password",
                cobbler_hostname => "$cobbler_hostname"
        }
}

