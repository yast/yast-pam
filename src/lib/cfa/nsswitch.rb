# Copyright (c) [2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "cfa/base_model"
require "yast2/target_file"

Yast.import "FileUtils"

module CFA
  # Model to handle the Name Service Switch configuration file
  #
  # @note The NSS configuration file cannot be overwritten partially, which means that once
  #   /etc/nsswith.conf (local) file exists in the system /usr/etc/nsswitch.conf (vendor) will be
  #   completely ignored.  In other words, it does not allow to override single entries.
  #   Consequently, to guarantee not losing full distribution provided configuration the content
  #   will be read from the vendor file if the local one does not exist yet but will be always
  #   written to the local file.
  #
  # @example Reading service specifications of a database
  #   file = Nsswitch.new
  #   file.load
  #   file.services_for("hosts") #=> ["db", "files"]
  #
  # @example Writing service specifications for a database
  #   file = Nsswitch.new
  #   file.load
  #   file.update_entry("hosts", ["db", "files"])
  #   file.save
  #
  # @example Deleting a database entry
  #   file = Nsswitch.new
  #   file.load
  #   file.delete_entry("hosts")
  #   file.save
  #
  # @example Loading shortcut
  #   file = Nsswitch.load
  #   file.entries #=> ["passwd", "group", "shadow", "hosts", "networks", "aliases"]
  class Nsswitch < BaseModel
    include Yast::Logger

    # Path to local configuration file
    LOCAL_PATH = "/etc/nsswitch.conf".freeze
    private_constant :LOCAL_PATH

    # Path to vendor configuration file
    VENDOR_PATH = "/usr/etc/nsswitch.conf".freeze
    private_constant :VENDOR_PATH

    class << self
      # Instantiates and loads the file
      #
      # This method is basically a shortcut to instantiate and load the content in just one call.
      #
      # @param file_handler [#read,#write] something able to read/write a string (like File)
      # @return [Nsswitch] File with the already loaded content
      def load(file_handler: Yast::TargetFile)
        new(file_handler: file_handler).tap(&:load)
      end
    end

    attr_reader :load_path, :write_path

    # Constructor
    #
    # @param file_handler [#read,#write] something able to read/write a string (like File)
    #
    # @see CFA::BaseModel#initialize
    def initialize(file_handler: Yast::TargetFile)
      # Path for loading the content
      @load_path = Yast::FileUtils.Exists(LOCAL_PATH) ? LOCAL_PATH : VENDOR_PATH
      # Path for writing the content, always the local file
      @write_path = LOCAL_PATH

      super(AugeasParser.new("nsswitch.lns"), load_path, file_handler: file_handler)
    end

    # Loads the file content
    #
    # If the file does not exist, consider it as empty.
    #
    # @see CFA::BaseModel#load
    def load
      super
      fix_collection_names(data)
      @current_content = @parser.serialize(data)
    rescue Errno::ENOENT # PATH does not exist yet
      self.data = @parser.empty
      @loaded = true
    end

    # Returns a list of defined databases
    #
    # @return [Array<String>] List of database names
    def entries
      databases.keys
    end

    # Service specifications for given database name
    #
    # @param db_name [String] the database name, e.g., "passwd" or "hosts"
    #
    # @return [Array<String>] database service specifications or empty list if db_name is not found
    def services_for(db_name)
      databases[db_name]&.services || []
    end

    # Update (or create if it does not exist yet) the entry for given database name
    #
    #
    # @note Current services, if any, are completely replaced
    #
    # @see #entry_for
    # @see DatabaseEntry#services=
    #
    # @param db_name [String] the database name, e.g., "passwd" or "hosts"
    # @param services [Array<String>] service specifications for the database
    def update_entry(db_name, services)
      database = entry_for(db_name)
      database.services = services
    end

    # Delete entry for given database name
    #
    # @param db_name [String] the database db_name, e.g., "passwd" or "hosts"
    def delete_entry(db_name)
      data.delete(database_matcher(db_name))
    end

    # Writes the current content to /etc/nsswitch.conf
    #
    # @see CFA::BaseModel#save
    def save
      @parser.file_name = write_path if @parser.respond_to?(:file_name=)
      content = @parser.serialize(data)

      if content != @current_content
        @file_handler.write(write_path, content)
        @current_content = content
      end
    end

  private

    # Return the CFA::Matcher for given database name
    #
    # @param db_name [String] the database name, e.g., "passwd" or "hosts"
    #
    # @return [CFA::Matcher]
    def database_matcher(db_name)
      CFA::Matcher.new { |k, v| k == "database[]" && v.value == db_name }
    end

    # Find or create the DatabaseEntry for given database name
    #
    # @param db_name [String] the database name, e.g., "passwd" or "hosts"
    #
    # @return [DatabaseEntry]
    def entry_for(db_name)
      return databases[db_name] if databases.keys.include?(db_name)

      database = CFA::AugeasTreeValue.new(CFA::AugeasTree.new, db_name)
      data.add("database[]", database)
      DatabaseEntry.new(database)
    end

    # Available databases
    #
    # @return [Hash{String => DatabaseEntry}]
    def databases
      raw_databases.each_with_object({}) do |database, collection|
        name = database[:value].value.to_s
        collection[name] = DatabaseEntry.new(database[:value])
      end
    end

    # Available databases in internal structure
    #
    # @return [Array<Hash{Symbol => CFA::AugeasTreeValue, String, Symbol}>]
    def raw_databases
      data.select(CFA::Matcher.new(collection: "database"))
    end

    # Known collection keys
    COLLECTION_KEYS = ["database", "service"].freeze
    private_constant :COLLECTION_KEYS

    # Fix collection names adding the missing "[]"
    #
    # When a collection has only one element, Augeas does not add "[]" suffix, reason why is
    # necessary to fix at least those collections that are going to be hitted for either, read or
    # write.
    #
    # @param tree [AugeasTree,AugeasTreeValue]
    def fix_collection_names(tree)
      tree.data.each do |entry|
        entry[:key] << "[]" if COLLECTION_KEYS.include?(entry[:key])
        fix_collection_names(entry[:value].tree) if entry[:value].is_a?(AugeasTreeValue)
        fix_collection_names(entry[:value]) if entry[:value].is_a?(AugeasTree)
      end
    end

    # Internal class for managing database entries
    class DatabaseEntry
      # Constructor
      #
      # @param data [CFA::AugeasTreeValue]
      def initialize(data)
        @data = data
      end

      # The database name
      #
      # @return [String]
      def name
        data.value
      end

      # The database service specifications
      #
      # @return [Array<String>]
      def services
        data.tree.collection("service").map(&:to_s)
      end

      # Set service specifications
      #
      # TODO: add support for reactions
      #
      # @param services [Array<String>]
      def services=(services)
        data.tree.delete("service[]")
        data.tree.delete("reaction[]")

        services.each { |service| data.tree.add("service[]", service) }
      end

    private

      attr_reader :data
    end
  end
end
