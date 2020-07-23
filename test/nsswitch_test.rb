#!/usr/bin/env rspec
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

require_relative "test_helper"
require "tmpdir"

Yast.import "Nsswitch"

describe Yast::Nsswitch do
  subject(:nsswitch) { Yast::Nsswitch }

  let(:tmpdir) { Dir.mktmpdir }
  let(:original_data_example) { File.join(DATA_PATH, "nsswitch.conf/custom/etc") }
  let(:file_path) { "#{tmpdir}/etc/nsswitch.conf" }

  around do |example|
    begin
      FileUtils.cp_r(original_data_example, tmpdir)
      change_scr_root(tmpdir, &example)
    ensure
      FileUtils.remove_entry(tmpdir)
    end
  end

  describe "#ReadDb" do
    context "when given an available database entry" do
      let(:db_name) { "hosts" }

      it "returns its defined service specifications" do
        expect(nsswitch.ReadDb(db_name)).to eq(["db", "files"])
      end
    end

    context "when given a not available database entry" do
      let(:db_name) { "ethers" }

      it "returns an empty list" do
        expect(nsswitch.ReadDb(db_name)).to eq([])
      end
    end
  end

  describe "#WriteDb" do
    context "when given an already defnied database entry" do
      it "replaces its service specifications with given ones" do
        expect(File.read(file_path)).to match(/hosts:\s+db files/)

        nsswitch.WriteDb("hosts", ["nis", "files"])
        nsswitch.Write

        expect(File.read(file_path)).to match(/hosts:\s+nis files/)
      end

      context "when given not defined yet database entry" do
        it "adds it to the configuration" do
          expect(File.read(file_path)).to_not match(/ethers:/)

          nsswitch.WriteDb("ethers", ["nis", "files"])
          nsswitch.Write

          expect(File.read(file_path)).to match(/ethers:\s+nis files/)
        end
      end
    end
  end

  describe "#WriteAutofs" do
    let(:db_name) { "automount" }

    context "when services should start" do
      let(:start) { true }

      context "and it is not enabled yet" do
        let(:source) { "nis" }

        it "enables it by adding it to service specifications" do
          nsswitch.WriteAutofs(start, source)
          nsswitch.Write

          expect(File.read(file_path)).to match(/automount:\s+nis/)
        end
      end
    end

    context "when services should not start" do
      let(:start) { false }

      context "but it is enabled" do
        let(:source) { "nis" }

        before do
          nsswitch.WriteDb(db_name, ["nis", "ldap"])
          nsswitch.Write
        end

        it "disables it by removing it from service specifications" do
          expect(File.read(file_path)).to match(/automount:\s+nis ldap/)

          nsswitch.WriteAutofs(start, source)
          nsswitch.Write

          expect(File.read(file_path)).to match(/automount:\s+ldap/)
          expect(File.read(file_path)).to_not match(/automount:\s+nis/)
        end
      end
    end
  end
end
