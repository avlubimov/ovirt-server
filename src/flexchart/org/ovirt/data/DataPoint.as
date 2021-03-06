/*
 Copyright (C) 2008 Red Hat, Inc.
 Written by Steve Linabery <slinabery@redhat.com>

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; version 2 of the License.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 MA  02110-1301, USA.  A copy of the GNU General Public License is
 also available at http://www.gnu.org/copyleft/gpl.html.
*/

package org.ovirt.data {

  public class DataPoint {

    private var timestamp:Date;
    private var value:Number;
    private var description:String;
    private var resolution:int;
    private var nodeName:String;

    public function DataPoint (timestamp:Date, value:Number,
                               description:String, resolution:int,
			       nodeName:String) {
      this.timestamp = timestamp;
      this.value = value;
      this.description = description;
      this.resolution = resolution;
      this.nodeName = nodeName;
    }

    public function getTimestamp():Date {
      return timestamp;
    }

    public function getValue():Number {
      return value;
    }

    public function getDescription():String {
      return description;
    }

    public function getResolution():int {
      return resolution;
    }

    public function getNodeName():String {
      return nodeName;
    }

  }
}
