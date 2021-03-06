#
# Copyright (C) 2008 Red Hat, Inc.
# Written by Darryl L. Pierce <dpierce@redhat.com>.
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

require File.dirname(__FILE__) + '/../test_helper'
require 'test/unit'
require 'managed_node_configuration'

# Performs unit tests on the +ManagedNodeConfiguration+ class.
#
class ManagedNodeConfigurationTest < ActiveSupport::TestCase
  fixtures :bonding_types
  fixtures :bondings
  fixtures :bondings_nics
  fixtures :boot_types
  fixtures :hosts
  fixtures :nics
  fixtures :networks
  fixtures :ip_addresses

  def setup
    @host_with_dhcp_card = hosts(:fileserver_managed_node)
    @host_with_ip_address = hosts(:ldapserver_managed_node)
    @host_with_multiple_nics = hosts(:buildserver_managed_node)
    @host_with_bondings = hosts(:mailservers_managed_node)
    @host_with_dhcp_bondings = hosts(:mediaserver_managed_node)
  end

  # Ensures that network interfaces uses DHCP when no IP address is specified.
  #
  def test_generate_with_no_ip_address
    nic = @host_with_dhcp_card.nics.first

    expected = <<-HERE
# THIS FILE IS GENERATED!
ifcfg=#{nic.mac}|breth0|BOOTPROTO=#{nic.boot_protocol}|TYPE=Bridge|PEERDNS=no|ONBOOT=yes
ifcfg=#{nic.mac}|eth0|BRIDGE=breth0|ONBOOT=yes
    HERE

    result = ManagedNodeConfiguration.generate(
      @host_with_dhcp_card,
      {"#{nic.mac}" => 'eth0'}
    )

    assert_equal expected, result
  end

  # Ensures that network interfaces use the IP address when it's provided.
  #
  def test_generate_with_ip_address_and_bridge
    nic = @host_with_ip_address.nics.first

    expected = <<-HERE
# THIS FILE IS GENERATED!
ifcfg=#{nic.mac}|breth0|BOOTPROTO=#{nic.boot_protocol}|IPADDR=#{nic.ip_address}|NETMASK=#{nic.netmask}|BROADCAST=#{nic.broadcast}|GATEWAY=#{nic.gateway}|TYPE=Bridge|PEERDNS=no|ONBOOT=yes
ifcfg=#{nic.mac}|eth0|BRIDGE=breth0|ONBOOT=yes
    HERE

    result = ManagedNodeConfiguration.generate(
      @host_with_ip_address,
      {"#{nic.mac}" => 'eth0'}
    )

    logger.info "expected: #{expected.class}, #{expected.length}, #{expected}"
    logger.info "result: #{result.class}, #{result.size}, #{result}"
    assert_equal expected, result
  end

  # Ensures that more than one NIC is successfully processed.
  #
  def test_generate_with_multiple_nics
    nic1 = @host_with_multiple_nics.nics[0]
    nic2 = @host_with_multiple_nics.nics[1]

    expected = <<-HERE
# THIS FILE IS GENERATED!
ifcfg=#{nic1.mac}|breth0|BOOTPROTO=#{nic1.boot_protocol}|IPADDR=#{nic1.ip_address}|NETMASK=#{nic1.netmask}|BROADCAST=#{nic1.broadcast}|GATEWAY=#{nic1.gateway}|TYPE=Bridge|PEERDNS=no|ONBOOT=yes
ifcfg=#{nic1.mac}|eth0|BRIDGE=breth0|ONBOOT=yes
ifcfg=#{nic2.mac}|breth1|BOOTPROTO=#{nic2.boot_protocol}|TYPE=Bridge|PEERDNS=no|ONBOOT=yes
ifcfg=#{nic2.mac}|eth1|BRIDGE=breth1|ONBOOT=yes
    HERE

    result = ManagedNodeConfiguration.generate(
      @host_with_multiple_nics,
      {
        "#{nic1.mac}" => 'eth0',
        "#{nic2.mac}" => 'eth1'
      })

    assert_equal expected, result
  end

  # Ensures that the bonding portion is created if the host has a bonded
  # interface defined.
  #
  def test_generate_with_bonding
    bonding = @host_with_bondings.bondings.first

    nic1 = bonding.nics[0]
    nic2 = bonding.nics[1]

    expected = <<-HERE
# THIS FILE IS GENERATED!
bonding=#{bonding.interface_name}
ifcfg=none|#{bonding.interface_name}|BONDING_OPTS="mode=#{bonding.bonding_type.mode} miimon=100"|BRIDGE=br#{bonding.interface_name}|ONBOOT=yes
ifcfg=none|br#{bonding.interface_name}|BOOTPROTO=dhcp|TYPE=Bridge|PEERDNS=no|ONBOOT=yes
ifcfg=#{nic1.mac}|eth0|MASTER=#{bonding.interface_name}|SLAVE=yes|ONBOOT=yes
ifcfg=#{nic2.mac}|eth1|MASTER=#{bonding.interface_name}|SLAVE=yes|ONBOOT=yes
HERE

    result = ManagedNodeConfiguration.generate(
      @host_with_bondings,
      {
        "#{nic1.mac}" => 'eth0',
        "#{nic2.mac}" => 'eth1'
      })

    assert_equal expected, result
  end

  # Ensures that the generated bonding supports DHCP boot protocol.
  #
  def test_generate_with_dhcp_bonding
    bonding = @host_with_dhcp_bondings.bondings.first

    nic1 = bonding.nics[0]
    nic2 = bonding.nics[1]

    expected = <<-HERE
# THIS FILE IS GENERATED!
bonding=#{bonding.interface_name}
ifcfg=none|#{bonding.interface_name}|BONDING_OPTS="mode=#{bonding.bonding_type.mode} miimon=100"|BRIDGE=br#{bonding.interface_name}|ONBOOT=yes
ifcfg=none|br#{bonding.interface_name}|BOOTPROTO=#{bonding.boot_protocol}|TYPE=Bridge|PEERDNS=no|ONBOOT=yes
ifcfg=#{nic1.mac}|eth0|MASTER=#{bonding.interface_name}|SLAVE=yes|ONBOOT=yes
ifcfg=#{nic2.mac}|eth1|MASTER=#{bonding.interface_name}|SLAVE=yes|ONBOOT=yes
HERE

    result = ManagedNodeConfiguration.generate(
      @host_with_dhcp_bondings,
      {
        "#{nic1.mac}" => 'eth0',
        "#{nic2.mac}" => 'eth1'
      })

    assert_equal expected, result
  end

end
