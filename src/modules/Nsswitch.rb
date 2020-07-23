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

      @cfa_model = CFA::Nsswitch.load
    end

    # Reads a database entry from nsswitch_conf and returns it as a list
    #
    # @see CFA::Nsswitch#services_for
    #
    # @param db_name [String] database entry name, e.g. "passwd"
    def ReadDb(db_name)
      cfa_model.services_for(db_name)
    end


    # Writes a database entry as a list to nsswitch_conf
    #
    # @see CFA::Nsswitch#update_entry
    #
    # @param db_name [String] database entry name, e.g. "passwd"
    # @param services [Array<String>] service specs, e.g. ["files", "nis"]
    def WriteDb(db_name, services)
      cfa_model.update_entry(db_name, services)
    end

    # Configures the name service switch for autofs according to chosen settings
    #
    # @param start [Boolean] whether autofs and service (ldap/nis) should be started
    # @param source [String] source for automounter data (ldap/nis)
    #
    # @return [Boolean] true if changes are done; false otherwise
    def WriteAutofs(start, source)
      # nsswitch automount:
      # bracket options not allowed
      automount_services = cfa_model.services_for("automount")
      enabled = automount_services.include?(source)

      # enable it if it is not enabled yet and both services run
      automount_services -= [source] if !start && enabled

      # enable it if it is not enabled yet and both services run
      if start && !enabled
        automount_services += [source]
      # disable it if it is enabled and either service does not run
      elsif !start && enabled
        automount_services -= [source]
      end

      cfa_model.update_entry("automount", automount_services)
      cfa_model.save

      true
    rescue CFA::AugeasSerializingError
      Report.Error(Message.ErrorWritingFile("/etc/nsswitch.conf"))

      false
    end

    # Writes the edited files to the disk
    # @return true on success
    def Write
      cfa_model.save
    end

    publish :function => :ReadDb, :type => "list <string> (string)"
    publish :function => :WriteDb, :type => "boolean (string, list <string>)"
    publish :function => :WriteAutofs, :type => "boolean (boolean, string)"
    publish :function => :Write, :type => "boolean ()"

    private

    attr_reader :cfa_model
  end

  Nsswitch = NsswitchClass.new
  Nsswitch.main
end
