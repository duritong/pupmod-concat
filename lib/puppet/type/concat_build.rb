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

Puppet::Type.newtype(:concat_build) do
  @doc = "Build file from fragments"

  def extractexe(cmd)
    # easy case: command was quoted
    if cmd =~ /^"([^"]+)"/
      $1
    else
      cmd.split(/ /)[0]
    end
  end

  def validatecmd(cmd)
    exe = extractexe(cmd)
    fail Puppet::Error, "'#{cmd}' is unqualifed" unless File.expand_path(exe) == exe
  end

  newparam(:clean_comments) do
    desc "If a line begins with the specified string it will not be printed in the output file."
  end

  newparam(:clean_whitespace) do
    desc "Cleans whitespace.  Can be passed an array.  'lines' will cause the 
          output to not contain any blank lines. 'all' is equivalent to 
          [leading, trailing, lines]"
    munge do |value|
      value = [*value]
      if value.include?('all')
        ['leading', 'trailing', 'lines']
      else
        value.uniq
      end
    end

    validate do |value|
      value = [*value]
      if value.include?('none') && value.uniq.length > 1
        fail Puppet::Error, "You cannot specify 'none' with any other options"
      end
    end

    newvalues(:leading, :trailing, :lines, :all, :none)
    defaultto [:none]
  end

  newparam(:file_delimiter) do
    desc "Acts as the delimiter between concatenated file fragments. For
	  instance, if you have two files with contents 'foo' and 'bar', the
	  result with a file_delimiter of ':' will be a file containing
          'foo:bar'."
    defaultto "\n"
  end

  newparam(:name) do
    isnamevar
    validate do |value|
      fail Puppet::Error, "concat_name cannot include '../'!" if value =~ /\.\.\//
    end
  end

  newparam(:onlyif) do
    desc "Copy file to target only if this command exits with status '0'"
    validate do |cmds|
      [*cmds].each do |cmd|
        @resource.validatecmd(cmd)
      end
    end

    munge do |cmds|
      [*cmds]
    end
  end

  newparam(:sort, :boolean => true) do
    desc "Sort the built file. This tries to sort in a human fashion with 
	  1 < 2 < 10 < 20 < a, etc..  sort. Note that this will need to read
          the entire file into memory

          Example Sort:

          ['a','1','b','10','2','20','Z','A']

          translates to

          ['1','2','10','20','a','A','b','Z']

          Note: If you use a file delimiter with this, it *will not* be sorted!"
    newvalues(:true, :false)
    defaultto :false
  end

  newparam(:squeeze_blank, :boolean => true) do
    desc "Never output more than one blank line"
    newvalues(:true, :false)
    defaultto :false
  end

  newparam(:target) do
    desc "Fully qualified path to copy output file to"
    validate do |path|
      unless path =~ /^\/$/ || path =~ /^\/[^\/]/
        fail Puppet::Error, "File paths must be fully qualified, not '#{path}'"
      end
    end
  end

  newparam(:parent_build) do
    desc "Specify the parent to this build step. Only needed for multiple
          staged builds. Can be an array."
  end

  newparam(:quiet, :boolean => true) do
    desc "Suppress errors when no fragments exist for build"
    newvalues(:true, :false)
    defaultto :false
  end

  newparam(:unique) do
    desc "Only print unique lines to the output file. Sort takes precedence.
          This does not affect file delimiters.

	  true: Uses Ruby's Array.uniq function. It will remove all duplicates
          regardless  of where they are in the file.
 
	  uniq: Acts like the uniq command found in GNU coreutils and only
          removes consecutive duplicates."

    newvalues(:true, :false, :uniq)
    defaultto :false
  end

  newproperty(:order, :array_matching => :all) do
    desc "Array containing ordering info for build"

    defaultto ["*"]

    def retrieve
      resource[:order].join(',')
    end

    def insync?(is)
      # Build the temporary file, and then diff it against the actual one
      provider.build_file
      File.exists?(@resource[:target]) && diff_file
    end

    def sync
      # Move the tempfile into place
      provider.copy_file
    end

    def change_to_s(currentvalue, newvalue)
      "#{[*newvalue].join(',')} used for ordering"
    end
  end

  autorequire(:concat_build) do
    # resource contains all concat_build resources from the catalog that are
    # children of this concat_build
    resources = catalog.resources.find_all { |r| r.is_a?(Puppet::Type.type(:concat_build)) && r[:parent_build] && [*r[:parent_build]].include?(self[:name]) }
    resources.each { |r| debug "Autorequiring #{r}" }
    resources
  end

  autorequire(:concat_fragment) do
    # resource contains all concat_fragment resources from the catalog that
    # belong to this concat_build
    resources = catalog.resources.find_all { |r| r.is_a?(Puppet::Type.type(:concat_fragment)) && r[:name] =~ /^#{self[:name]}\+.+/ }
    if resources.empty? && !self.quiet?
      err "No fragments specified for group #{self[:name]}!"
    end

    if self[:parent_build]
      found_parent = false
      parent_builds = [*self[:parent_build]]
      parent_builds.each do |parent_build|
        # Checks to see if there is a concat_build for each parent_build specified
        found_parent = !catalog.resources.any? { |r| r.is_a?(Puppet::Type.type(:concat_build)) && r[:name].eql?(parent_build)}
        if found_parent && !self.quiet?
          warning "No concat_build found for parent_build #{parent_build}"
        end
        # frags contains all concat_fragment resources for the parent concat_build
        frags = catalog.resources.find_all { |r| r.is_a?(Puppet::Type.type(:concat_fragment)) && r[:name] =~ /^#{parent_build}\+.+/ }
        resources.push(*frags)
      end
      err "No concat_build found for any of #{parent_builds.join(",")}" unless found_parent
    end
    resources.each { |r| debug "Autorequiring #{r}" }
    resources
  end
  
  autorequire(:file) do
    [ Facter.value(:concat_basedir), fragments_dir, output_dir, my_fragments_dir ]
  end

  def diff_file
    output_file = File.join(Facter.value(:concat_basedir),"#{@resource[:name]}.out")
    require 'puppet/util/diff'
    diffs = Puppet::Util::Diff.diff(@resource[:target],output_file)
    puts diffs unless (result = diffs.empty?)
    result
  end
  
  def generate
    should = self.should(:ensure) || :present
    resources = []
    if (should == :present)
      unless catalog.resource(:file, Facter.value(:concat_basedir))
        resources << Puppet::Type.type(:file).new(
          :name => Facter.value(:concat_basedir),
          :ensure => 'directory',
          :purge => true,
          :recurse => true,
          :force => true,
          :mode => "0600"
        )
      end
      unless catalog.resource(:file, fragments_dir)
        resources << Puppet::Type.type(:file).new(
          :name => fragments_dir,
          :ensure => 'directory',
          :purge => true,
          :recurse => true,
          :force => true,
          :mode => "0600"
        )
      end
      unless catalog.resource(:file, output_dir)
        resources << Puppet::Type.type(:file).new(
          :name => output_dir,
          :ensure => 'directory',
          :purge => true,
          :recurse => true,
          :force => true,
          :mode => "0600"
        )
      end
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
    end
    resources
  end
  
  def my_fragments_dir
    @my_fragments_dir ||= File.join(fragments_dir,self[:name])
  end
  
  def output_dir
    @output_dir ||= File.join(Facter.value(:concat_basedir),'output')
  end
  
  def fragments_dir
    @fragments_dir ||= File.join(Facter.value(:concat_basedir),'fragments')
  end
end
