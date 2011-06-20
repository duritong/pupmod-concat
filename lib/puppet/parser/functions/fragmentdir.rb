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
module Puppet::Parser::Functions
    newfunction(:fragmentdir, :type => :rvalue, :doc => "Returns the fragment directory for a given concat build.") do |args|
        "/var/lib/puppet/concat/fragments/#{args}"
        File.join(lookupvar('concat_basedir'),'fragments',args.first)
    end
end
