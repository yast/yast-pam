#!rspec
# Copyright (c) [2022] SUSE LLC
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

Yast.import "Autologin"

describe Yast::Autologin do
  subject(:nsswitch) { Yast::Autologin }

  before do
    # reset module before each run
    subject.main
    allow(Yast::Package).to receive(:Available).and_return(false)
  end

  describe ".available" do
    it "returns true if Read found a supported DM" do
      allow(Yast::Package).to receive(:Available).with("gdm").and_return(true)

      subject.Read
      expect(subject.available).to eq true
    end

    it "returns true if Read did not find any supported DM" do
      subject.Read
      expect(subject.available).to eq false
    end
  end
end

