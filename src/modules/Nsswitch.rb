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

# File:	modules/Nsswitch.ycp
# Module:	yast2-pam
# Summary:	Configuration of /etc/nsswitch.conf
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
# Flags:	Stable
#
# $Id$
require "yast"

module Yast
  class NsswitchClass < Module
    def main

      Yast.import "Message"
      Yast.import "Report"
    end

    # Reads a database entry from nsswitch_conf and returns it as a list
    # @param [String] db eg. "passwd"
    # @return   eg. ["files", "nis"]
    def ReadDb(db)
      db_s = Convert.to_string(
        SCR.Read(Builtins.add(path(".etc.nsswitch_conf"), db))
      )
      db_s = "" if db_s == nil
      Builtins.filter(Builtins.splitstring(db_s, " \t")) { |s| s != "" }
    end


    # Writes a database entry as a list to nsswitch_conf
    # @param [String] db eg. "passwd"
    # @param [Array<String>] entries eg. ["files", "nis"]
    # @return success?
    def WriteDb(db, entries)
      entries = deep_copy(entries)
      # if there are no entries, delete the key using nil
      entry = Builtins.mergestring(entries, " ")
      SCR.Write(
        Builtins.add(path(".etc.nsswitch_conf"), db),
        entry == "" ? nil : entry
      )
    end
    # Configures the name service switch for autofs
    # according to chosen settings
    # @param [Boolean] start autofs and service (ldap/nis) should be started
    # @param [String] source for automounter data (ldap/nis)
    # @return success?
    def WriteAutofs(start, source)
      ok = true

      # nsswitch automount:
      # bracket options not allowed, order does not matter
      automount_l = ReadDb("automount")
      enabled = Builtins.contains(automount_l, source)
      # enable it if it is not enabled yet and both services run
      if start && !enabled
        automount_l = Builtins.add(automount_l, source)
        ok = WriteDb("automount", automount_l)
        ok = ok && SCR.Write(path(".etc.nsswitch_conf"), nil)
      # disable it if it is enabled and either service does not run
      elsif !start && enabled
        automount_l = Builtins.filter(automount_l) { |s| s != source }
        ok = WriteDb("automount", automount_l)
        ok = ok && SCR.Write(path(".etc.nsswitch_conf"), nil)
      end

      Report.Error(Message.ErrorWritingFile("/etc/nsswitch.conf")) if !ok
      ok
    end

    # Writes the edited files to the disk
    # @return true on success
    def Write
      SCR.Write(path(".etc.nsswitch_conf"), nil)
    end

    publish :function => :ReadDb, :type => "list <string> (string)"
    publish :function => :WriteDb, :type => "boolean (string, list <string>)"
    publish :function => :WriteAutofs, :type => "boolean (boolean, string)"
    publish :function => :Write, :type => "boolean ()"
  end

  Nsswitch = NsswitchClass.new
  Nsswitch.main
end
