# -*- coding: utf-8 -*-

require 'time'
require 'fileutils'
require 'digest/md5'
require 'stringio'
require 'modruby/request'

module ModRuby

class RuntimeError < ::RuntimeError

  attr_reader :e, :fileName, :className

  def initialize(fileName, className, e)
    @fileName  = fileName
    @className = className
    @e         = e
  end

  def to_s
    return @e.to_s
  end

end

class Redirect < RuntimeError

  attr_reader :url

  def initialize(url)
    @url = url
  end

  def to_s
    return @url.to_s
  end

end

class RequestTermination < Exception

  def initialize()
  end

  def to_s
    'Request terminated'
  end

end

# Print a backtrace from the exception. 
def ModRuby.backtrace(e, message)

  msg = sprintf("%-11s: %s\n", e.class, e.to_s)

  # Escape HTML
  msg.gsub!( /[&\"<>]/, 
             { 
               '&' => '&amp;',
               '"' => '&quot;',
               '<' => '&lt;',
               '>' => '&gt;' 
             })

  out = "<pre>ModRuby BACKTRACE\n\n"
  out << "Handled by : #{message}\n"
  out << msg
  out << "Stack:\n"
  i = 1
  e.backtrace.each do |stack|
    out << sprintf("%3i. %s\n", i, stack)
    i += 1
  end
  
  return out
end

end # module ModRuby

#-------------------------------------------------------------------------------
# Code for running anonymous Ruby/RHTML scripts
#-------------------------------------------------------------------------------

# Cleanroom for running scripts and RHTML files
class BlankSlate
  instance_methods.each do |name|
    class_eval do
      undef_method name unless name =~ /__|instance_eval|binding|object_id/
    end
  end

  def initialize(req, code, file)
    @request = req
    Kernel::eval(code, binding, file)
  end
end

# Simple class to set up simple environment to run scripts and catch errors
class Runner
  
  def initialize(req)
    @request = req
  end

  def setup()
    begin
      # Change directory to the document root
      file = @request.cgi['SCRIPT_FILENAME']

      FileUtils.cd(file[0..file.rindex('/')-1])

      # Store the current (real) stdout
      previous = $stdout
  
      # Create a new stringio object to capture diverted stdout
      out = StringIO.new
      
      # Redirect standard out to stringio buffer
      $stdout = out
      
      # Store this so view's and/or contollers can get to it
      @request.out = out
      
      yield file
      
    rescue Exception
      # Something blew up. Print a stack trace
      @request.puts '<pre>' + ModRuby.backtrace($!, 'ModRuby Turnstile')

      # No matter what, restore stdout
      $stdout = previous
    end

    # Print the content generated by the method to the CGI stream.
    @request.puts out.string()
  end

  def runScript()
    setup do |file|
      BlankSlate.new(@request, File.read(file), file)
    end
  end

  def runRhtml()
    setup do |file|
      code = ModRuby::RHTML::compile(file)
      BlankSlate.new(@request, code, file)
    end
  end

end
