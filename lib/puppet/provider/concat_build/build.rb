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
Puppet::Type.type(:concat_build ).provide(:concat_build) do
  require 'fileutils'

  desc "concat_build provider"

  def build_file
    FileUtils.mkdir_p(output_dir) unless File.directory?(output_dir)
    fail Puppet::Error, "The fragments directory at '#{fragments_dir}' does not exist!" if !File.directory?(fragments_dir) && !@resource.quiet?

    f = File.open(File.join(output_dir,"#{@resource[:name]}.out"), "w+")
    input_lines = []
    Dir.chdir(fragments_dir) do
      [*@resource[:order]].each do |pattern|
        Dir.glob(pattern).sort_by{ |k| human_sort(k) }.each do |file|

          prev_line = nil
          File.open(file).each do |line|

            if @resource.squeeze_blank? && line =~ /^\s*$/
              next if prev_line == :whitespace
              prev_line = :whitespace
            end

            unless clean_line(line).nil?
		          # This is a bit hackish, but it would be nice to keep as much
		          # of the file out of memory as possible in the general case.
              if @resource.sort? || !@resource[:unique].eql?(:false)
                input_lines.push(line)
              else
                f.puts(line)
              end
            end
          end
          if !@resource.sort? && @resource[:unique].eql?(:false)
            # Separate the files by the specified delimiter.
            f.seek(-1, IO::SEEK_END)
            if f.getc.chr.eql?("\n")
              f.seek(-1, IO::SEEK_END)
              f.print(String(@resource[:file_delimiter]))
            end
          end
        end
      end
    end

    unless input_lines.empty?
      input_lines = input_lines.sort_by{ |k| human_sort(k) } if @resource.sort?
      unless @resource[:unique].eql?(:false)
        if @resource[:unique].eql?(:uniq)
          require 'enumerator'
          input_lines = input_lines.enum_with_index.map { |x,i|
            x.eql?(input_lines[i+1]) ? nil : x
          }.compact
        else
          input_lines = input_lines.uniq
        end
      end

      f.puts(input_lines.join(@resource[:file_delimiter]))
    else
      # Ensure that the end of the file is a '\n'
      f.seek(-(String(@resource[:file_delimiter]).length), IO::SEEK_END)
      curpos = f.pos
      unless f.getc.chr.eql?("\n")
        f.seek(curpos)
        f.print("\n")
      end
      f.truncate(f.pos)
    end

    f.close

  rescue Exception => e
    fail Puppet::Error, e
  end
  
  def copy_file
    # This time for real - move the built file into the fragments dir
    FileUtils.touch(File.join(fragments_dir,'.~concat_fragments'))
    if @resource[:target] && check_onlyif
      src = File.join(output_dir,"#{@resource[:name]}.out")
      debug "Copying #{src} to #{@resource[:target]}"
      FileUtils.cp(src, @resource[:target])
    elsif @resource[:target]
      debug "Not copying to #{@resource[:target]}, 'onlyif' check failed"
    elsif @resource[:onlyif]
      debug "Specified 'onlyif' without 'target', ignoring."
    end
  end

  private

  def fragments_dir
    @fragments_dir ||= File.join(Facter.value(:concat_basedir),"fragments",@resource[:name])
  end

  def output_dir
    @output_dir ||= File.join(Facter.value(:concat_basedir),"output")
  end

  # Return true if the command returns 0.
  def check_command(value)
    output, status = Puppet::Util::SUIDManager.run_and_capture([value])
    # The shell returns 127 if the command is missing.
    if status.exitstatus == 127
      raise ArgumentError, output
    end
 
    status.exitstatus == 0
  end

  def check_onlyif
    @resource[:onlyif].nil? || [*@resource[:onlyif]].all?{ |cmd| check_command(cmd) }
  end

  def clean_line(line)
    newline = nil
    line.sub!(/\s*$/, '') if [*@resource[:clean_whitespace]].include?('leading')
    line.sub!(/^\s*/, '') if [*@resource[:clean_whitespace]].include?('trailing')

    newline = line unless [*@resource[:clean_whitespace]].include?('lines') && line =~ /^\s*$/
    newline = nil if @resource[:clean_comments] && line =~ /^#{@resource[:clean_comments]}/

    newline
  end

  def human_sort(obj)
    # This regex taken from http://www.bofh.org.uk/2007/12/16/comprehensible-sorting-in-ruby
    obj.to_s.split(/((?:(?:^|\s)[-+])?(?:\.\d+|\d+(?:\.\d+?(?:[eE]\d+)?(?:$|(?![eE\.])))?))/ms).map { |v| Float(v) rescue v.downcase }
  end

end
