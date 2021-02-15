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
      nsswitch.reset
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
    it "changes given database without writing to the file" do
      expect(File.read(file_path)).to_not match(/ethers:/)
      expect(nsswitch.ReadDb("ethers")).to eq([])

      nsswitch.WriteDb("ethers", ["nis", "files"])

      expect(nsswitch.ReadDb("ethers")).to eq(["nis", "files"])
      expect(File.read(file_path)).to_not match(/ethers:/)
    end

    context "when given an already defined database entry" do
      it "replaces its service specifications with given ones" do
        expect(nsswitch.ReadDb("hosts")).to eq(["db", "files"])

        nsswitch.WriteDb("hosts", ["nis", "files"])

        expect(nsswitch.ReadDb("hosts")).to eq(["nis", "files"])
      end

      context "if the service specification is an empty array" do
        it "removes the database entry" do
          expect(nsswitch.ReadDb("hosts")).to eq(["db", "files"])

          nsswitch.WriteDb("hosts", [])

          expect(nsswitch.ReadDb("hosts")).to eq([])
        end
      end
    end

    context "when given not defined yet database entry" do
      it "adds it to the configuration" do
        expect(nsswitch.ReadDb("ethers")).to eq([])

        nsswitch.WriteDb("ethers", ["nis", "files"])

        expect(nsswitch.ReadDb("ethers")).to eq(["nis", "files"])
      end

      context "if the service specification is an empty array" do
        it "changes nothing" do
          expect(nsswitch.ReadDb("ethers")).to eq([])

          nsswitch.WriteDb("ethers", [])

          expect(nsswitch.ReadDb("ethers")).to eq([])
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

          expect(File.read(file_path)).to match(/automount:\s+ldap/)
          expect(File.read(file_path)).to_not match(/automount:\s+nis/)
        end
      end
    end
  end

  describe "#Write" do
    context "when everything is right" do
      it "returns true" do
        nsswitch.WriteDb("ethers", ["nis", "files"])
        expect(nsswitch.Write).to eq(true)
      end

      it "writes changes to the file" do
        expect(File.read(file_path)).to_not match(/ethers:/)
        expect(File.read(file_path)).to match(/hosts:/)
        expect(File.read(file_path)).to_not match(/netmasks:/)

        nsswitch.WriteDb("ethers", ["nis", "files"])
        # Test deleting entries
        nsswitch.WriteDb("hosts", [])
        nsswitch.WriteDb("netmasks", [])
        nsswitch.Write

        expect(File.read(file_path)).to match(/ethers:\s+nis files/)
        expect(File.read(file_path)).to_not match(/hosts:/)
        expect(File.read(file_path)).to_not match(/netmasks:/)
      end
    end

    context "when something is wrong" do
      before do
        allow(Yast::Report).to receive(:Error)
      end

      it "returns false" do
        # there is not support for actions yet
        nsswitch.WriteDb("ethers", ["nis [NOTFOUND=return]", "files"])
        expect(nsswitch.Write).to eq(false)
      end

      it "reports an error" do
        # there is not support for actions yet
        nsswitch.WriteDb("ethers", ["nis [NOTFOUND=return]", "files"])
        expect(Yast::Message).to receive(:ErrorWritingFile).with(/nsswitch\.conf/)
        expect(Yast::Report).to receive(:Error)
        nsswitch.Write
      end

      it "does not change the file" do
        expect(File.read(file_path)).to_not match(/ethers:/)

        # there is not support for actions yet
        nsswitch.WriteDb("ethers", ["nis [NOTFOUND=return]", "files"])
        nsswitch.Write

        expect(File.read(file_path)).to_not match(/ethers:\s+nis files/)
      end
    end
  end
end
