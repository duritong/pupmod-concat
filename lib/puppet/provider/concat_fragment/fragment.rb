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
Puppet::Type.type(:concat_fragment).provide(:concat_fragment) do
  require 'fileutils'

  desc "concat_fragment provider"

  def create
    group, fragment = @resource[:name].split('+',2)

    fragments_dir = File.join('/var/lib/puppet/concat/fragments',group)

    if File.file?(File.join(fragments_dir,'.~concat_fragments'))
      debug "Purging #{fragments_dir}!"
      FileUtils.rm_rf(fragments_dir)
    end

    FileUtils.mkdir_p(fragments_dir)
    File.open(File.join(fragments_dir,fragment), "w"){|f| f << @resource[:content] }
  rescue Exception => e
    fail Puppet::Error, e
  end
end
