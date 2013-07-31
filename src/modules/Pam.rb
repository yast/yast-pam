# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# File:	modules/Pam.ycp
# Package:	yast2-pam
# Summary:	YaST intrerface for /etc/pam.d/* files
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
# Flags:	Unstable
#
# $Id$
#
require "yast"

module Yast
  class PamClass < Module
    def main

    end

    # Query PAM configuration for status of given module
    # @param string PAM module (e.g. ldap, cracklib)
    # @return [Hash{String => Array}] keys are 'management groups' (e.g. auth), values
    # are lists of options
    def Query(mod)
      ret = {}
      out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Ops.add("/usr/sbin/pam-config -q --", mod)
        )
      )
      if Ops.get_integer(out, "exit", 0) != 0
        Builtins.y2warning("pam-config for %1 returned %2", mod, out)
        return deep_copy(ret)
      end
      Builtins.foreach(
        Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
      ) do |line|
        l = Builtins.splitstring(line, ":")
        next if line == "" || Ops.less_than(Builtins.size(l), 2)
        key = Ops.get_string(l, 0, "")
        Ops.set(
          ret,
          key,
          Builtins.filter(Builtins.splitstring(Ops.get_string(l, 1, ""), " \t")) do |o|
            o != ""
          end
        )
      end
      deep_copy(ret)
    end

    # Ask if given PAM module is enabled
    def Enabled(mod)
      Ops.greater_than(Builtins.size(Query(mod)), 0)
    end

    # Add options or new PAM module
    # @param string PAM module or option
    # @return success
    def Add(mod)
      out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Ops.add("/usr/sbin/pam-config -a --", mod)
        )
      )
      if Ops.get_integer(out, "exit", 0) != 0
        Builtins.y2warning("pam-config for %1 returned %2", mod, out)
        return false
      end
      true
    end

    # Remove options or PAM module
    # @param string PAM module or option
    # @return success
    def Remove(mod)
      out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Ops.add("/usr/sbin/pam-config -d --", mod)
        )
      )
      if Ops.get_integer(out, "exit", 0) != 0
        Builtins.y2warning("pam-config for %1 returned %2", mod, out)
        return false
      end
      true
    end

    # Add/Remove option or PAM module
    # @param string PAM module or option
    # @param boolean true for adding, false for removing
    # @return success
    def Set(mod, set)
      set ? Add(mod) : Remove(mod)
    end

    publish :function => :Query, :type => "map (string)"
    publish :function => :Enabled, :type => "boolean (string)"
    publish :function => :Add, :type => "boolean (string)"
    publish :function => :Remove, :type => "boolean (string)"
    publish :function => :Set, :type => "boolean (string, boolean)"
  end

  Pam = PamClass.new
  Pam.main
end
