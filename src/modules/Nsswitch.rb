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
require "cfa/nsswitch"

module Yast
  class NsswitchClass < Module
    def main
      Yast.import "Message"
      Yast.import "Report"
    end

    # Reads a database entry from nsswitch_conf and returns it as a list
    #
    # @see CFA::Nsswitch#services_for
    #
    # @param db_name [String] database entry name, e.g. "passwd"
    def ReadDb(db_name)
      cfa_model.services_for(db_name)
    end


    # Writes a database entry as a list to nsswitch_conf or deletes an existing
    # database entry
    #
    # @see CFA::Nsswitch#update_entry
    # @see CFA::Nsswitch#delete_entry
    #
    # @param db_name [String] database entry name, e.g. "passwd"
    # @param services [Array<String>] use a valid service specs (e.g. ["files", "nis"])
    #   to write an entry or an empty array to remove the existing entry
    def WriteDb(db_name, services)
      # For improved compatibility with the old implementation, check also [""]
      if services.empty? || services == [""]
        cfa_model.delete_entry(db_name)
      else
        cfa_model.update_entry(db_name, services)
      end
    end

    # Configures the name service switch for autofs according to chosen settings
    #
    # @see #Write
    #
    # @param start [Boolean] whether autofs and service (ldap/nis) should be started
    # @param source [String] source for automounter data (ldap/nis)
    #
    # @return [Boolean] true on success; false otherwise
    def WriteAutofs(start, source)
      automount_services = cfa_model.services_for("automount")

      if start
        automount_services |= [source]
      else
        automount_services -= [source]
      end

      cfa_model.update_entry("automount", automount_services)
      Write()
    end

    # Writes changes to the file
    #
    # @note sadly, this method will directly report to the user if something goes wrong.
    #
    # @return [Boolean] true on success; false otherwise
    def Write
      cfa_model.save
      true
    rescue CFA::AugeasSerializingError
      Report.Error(Message.ErrorWritingFile(cfa_model.write_path))

      false
    end

    # Convenience method to force the CFA model reloading for next action
    #
    # Especially useful for testing the behavior
    def reset
      @cfa_model = nil
    end

    publish :function => :ReadDb, :type => "list <string> (string)"
    publish :function => :WriteDb, :type => "boolean (string, list <string>)"
    publish :function => :WriteAutofs, :type => "boolean (boolean, string)"
    publish :function => :Write, :type => "boolean ()"

  private

    def cfa_model
      @cfa_model ||= CFA::Nsswitch.load
    end
  end

  Nsswitch = NsswitchClass.new
  Nsswitch.main
end
