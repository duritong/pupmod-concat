#
# Copyright (C) 2011 Onyx Point, Inc. <http://onyxpoint.com/>
#
# This file is part of the Onyx Point concat puppet module.
#
# The Onyx Point concat puppet module is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the License,
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.
#

Puppet::Type.newtype(:concat_fragment) do
  @doc = "Create a concat fragment"

  newproperty(:content) do

    def retrieve
      resource[:content]
    end

    def insync?(is)
      true
    end

    def sync
    end

    def change_to_s(currentvalue, newvalue)
      "executed successfully"
    end
  end

  newparam(:name) do
    isnamevar
    validate do |value|
      fail Puppet::Error, "name is missing group or name. Name format must be 'group+fragment_name'" if value !~ /.+\+.+/
      fail Puppet::Error, "name cannot include '../'!" if value =~ /\.\.\//
    end
  end

  # This is only here because, at this point, we can be sure that the catalog
  # has been compiled. This checks to see if we have a concat_build specified
  # for our particular concat_fragment group.
  autorequire(:file) do
    if catalog.resources.none?{ |r| r.is_a?(Puppet::Type.type(:concat_build)) && r[:name] == self[:name].split('+').first }
      err "No 'concat_build' specified for group #{self[:name].split('+').first}!"
    end
    [ my_fragments_dir ]
  end
  
  validate do
    fail Puppet::Error, "You must specify content" unless self[:content]
  end
  
  def frag_file
    @frag_file ||= File.join(Facter.value(:concat_basedir),"fragments",self[:name].split('+',2))
  end
  
  def generate
    resources = []
    unless catalog.resource(:file, my_fragments_dir)
      resources << Puppet::Type.type(:file).new(
        :name => my_fragments_dir,
        :ensure => 'directory',
        :purge => true,
        :recurse => true,
        :force => true,
        :mode => "0600"
      )
    end
    resources << Puppet::Type.type(:file).new(
      :name => frag_file,
      :content => self[:content],
      :before => "Concat_build[#{self[:name].split('+').first}]",
      :mode => "0600"
    )
  end
  
  def my_fragments_dir
    @my_fragments_dir ||= File.dirname(frag_file)
  end
end
