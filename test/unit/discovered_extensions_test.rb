require 'test_helper'

class FindDiscoveryRulesTest < ActiveSupport::TestCase
  include Foreman::Controller::DiscoveredExtensions

  setup do
    @facts = {
      "interfaces"       => "lo,eth0",
      "ipaddress"        => "192.168.100.42",
      "ipaddress_eth0"   => "192.168.100.42",
      "macaddress_eth0"  => "AA:BB:CC:DD:EE:FF",
      "discovery_bootif" => "AA:BB:CC:DD:EE:FF",
    }
    set_default_settings
  end

  test "no rule is found for empty rule set" do
    host = Host::Discovered.import_host(@facts)
    refute find_discovery_rule(host)
  end

  test "no rule is found out of one for a discovered host with no facts" do
    host = Host::Discovered.import_host(@facts)
    FactoryGirl.create(:discovery_rule, :search => "facts.foo = bar")
    refute find_discovery_rule(host)
  end

  test "no rule is found out of one for a discovered host with some facts" do
    host = Host::Discovered.import_host(@facts)
    FactoryGirl.create(:discovery_rule, :search => "facts.foo = doesnotexist")
    refute find_discovery_rule(host)
  end

  test "no rule is found out of two for a discovered host" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = xxx")
    FactoryGirl.create(:discovery_rule, :priority => 2, :search => "facts.somefact = zzz")
    refute find_discovery_rule(host)
  end

  test "rule out of one is found for a discovered host" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    assert_equal find_discovery_rule(host), r1
  end

  test "first rule out of two is found for a discovered host" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = x",
                       :organizations => [host.organization], :locations => [host.location])
    assert_equal find_discovery_rule(host), r1
  end

  test "second rule out of two is found for a discovered host" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = x",
                       :organizations => [host.organization], :locations => [host.location])
    r2 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    assert_equal find_discovery_rule(host), r2
  end

  test "first rule out of two with different priorities is found for a discovered host" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :name => "A", :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    r2 = FactoryGirl.create(:discovery_rule, :name => "B", :priority => 2, :search => "facts.somefact = abc",
                       :organizations => [host.organization], :locations => [host.location])
    assert_equal find_discovery_rule(host), r1
  end

  test "second rule out of two with different priorities is found for a discovered host" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :name => "A", :priority => 2, :search => "facts.somefact = abc",
                       :organizations => [host.organization], :locations => [host.location])
    r2 = FactoryGirl.create(:discovery_rule, :name => "B", :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    assert_equal find_discovery_rule(host), r2
  end

  test "older rule out of two is found for a discovered host" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                       :organizations => [host.organization], :locations => [host.location])
    r2 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location],
                            :created_at => Time.now + 1.day)
    assert_equal find_discovery_rule(host), r1
  end

  test "drained rule does not match for a discovered host" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc", :max_count => 1,
                            :organizations => [host.organization], :locations => [host.location])
    r2 = FactoryGirl.create(:discovery_rule, :priority => 2, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    FactoryGirl.create(:host, :discovery_rule => r1)
    assert_equal find_discovery_rule(host), r2
  end

  test "discovery rule is associated after auto provisioning" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    perform_auto_provision host, r1
    assert_equal host.primary_interface.managed, true
    assert_equal host.build, true
    assert_equal host.hostgroup_id, r1.hostgroup_id
    assert_equal host.discovery_rule_id, r1.id
  end

  test "auto provisioning fails for rule without a hostgroup" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    r1.hostgroup = nil
    exception = assert_raises(::Foreman::Exception) do
      perform_auto_provision host, r1
    end
    assert_match /No hostgroup associated with rule/, exception.message
  end

  test "existing rule revent from hostgroup deletion" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    assert_raises(ActiveRecord::RecordNotDestroyed) do
      r1.hostgroup.destroy!
    end
  end

  test "rules with incorrect syntax are skipped" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    FactoryGirl.create(:discovery_rule, :priority => 1, :search => '=!^$#@?x',
                       :organizations => [host.organization], :locations => [host.location])
    r2 = FactoryGirl.create(:discovery_rule, :priority => 2, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    assert_equal find_discovery_rule(host), r2
  end

  test "hostname is copied after auto provisioning" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    r1 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location])
    perform_auto_provision host, r1
    assert_equal host.name, "macaabbccddeeff"
  end

  test "attributes from hostgroup are copied after auto provisioning" do
    facts = @facts.merge({"somefact" => "abc"})
    host = Host::Discovered.import_host(facts)
    domain = FactoryGirl.create(:domain)
    subnet = FactoryGirl.create(:subnet_ipv4, :name => 'subnet_100', :network => '192.168.100.0', :organizations => [host.organization], :locations => [host.location])
    hostgroup = FactoryGirl.create(:hostgroup, :with_environment, :with_rootpass, :with_os, :subnet => subnet, :domain => domain)
    r1 = FactoryGirl.create(:discovery_rule, :priority => 1, :search => "facts.somefact = abc",
                            :organizations => [host.organization], :locations => [host.location], :hostgroup => hostgroup)
    assert managed_host = perform_auto_provision(host, r1)
    assert_empty managed_host.errors
    assert_equal hostgroup.environment, managed_host.environment
    assert_equal hostgroup.puppet_proxy, managed_host.puppet_proxy
    assert_equal hostgroup.puppet_ca_proxy, managed_host.puppet_ca_proxy
  end

  def setup_normal_renderer
    Setting[:safemode_render] = false
    @facts.merge!({"somefact" => "abc"})
  end

  def setup_safemode_renderer
    Setting[:safemode_render] = true
    @facts.merge!({"somefact" => "abc"})
  end

  [:normal_renderer, :safemode_renderer].each do |renderer_name|
    test "#{renderer_name} is properly configured" do
      send "setup_#{renderer_name}"
      if renderer_name == :normal_renderer
        assert Setting[:safemode_render] == false
      else
        assert Setting[:safemode_render] == true
      end
    end

    test "hostname falls back to original name on empty response via #{renderer_name}" do
      host = Host::Discovered.import_host(@facts)
      r1 = FactoryGirl.create(:discovery_rule,
                              :search => "facts.somefact = abc",
                              :hostname => '<%= "" %>',
                              :organizations => [host.organization],
                              :locations => [host.location])
      refute perform_auto_provision host, r1
      assert_equal "macaabbccddeeff", host.name
    end

    test "hostname is rendered after auto provisioning using #{renderer_name}" do
      host = Host::Discovered.import_host(@facts)
      r1 = FactoryGirl.create(:discovery_rule,
                              :search => "facts.somefact = abc",
                              :hostname => 'x<%= 1+1 %>',
                              :organizations => [host.organization],
                              :locations => [host.location])
      refute perform_auto_provision host, r1
      assert_equal "x2", host.name
    end

    test "function rand is renderer properly using #{renderer_name}" do
      host = Host::Discovered.import_host(@facts)
      r1 = FactoryGirl.create(:discovery_rule,
                              :search => "facts.somefact = abc",
                              :hostname => 'x<%= rand(4) %>',
                              :organizations => [host.organization],
                              :locations => [host.location])
      refute perform_auto_provision host, r1
      assert_match(/x[0123]/, host.name)
    end

    test "hostname attribute name is renderer properly using #{renderer_name}" do
      host = Host::Discovered.import_host(@facts)
      r1 = FactoryGirl.create(:discovery_rule,
                              :search => "facts.somefact = abc",
                              :hostname => 'x<%= @host.name %>',
                              :organizations => [host.organization],
                              :locations => [host.location])
      refute perform_auto_provision host, r1
      assert_equal "xmacaabbccddeeff", host.name
    end

    test "hostname attribute ip is renderer properly using #{renderer_name}" do
      host = Host::Discovered.import_host(@facts)
      r1 = FactoryGirl.create(:discovery_rule,
                              :search => "facts.somefact = abc",
                              :hostname => 'x<%= @host.ip.gsub(".","-") %>',
                              :organizations => [host.organization],
                              :locations => [host.location])
      refute perform_auto_provision host, r1
      assert_equal "x192-168-100-42", host.name
    end

    test "hostname attribute facts_hash is renderer properly using #{renderer_name}" do
      facts = @facts.merge({"somefact" => "abc"})
      host = Host::Discovered.import_host(facts)
      r1 = FactoryGirl.create(:discovery_rule,
                              :search => "facts.somefact = abc",
                              :hostname => 'x<%= @host.facts["somefact"] %>',
                              :organizations => [host.organization],
                              :locations => [host.location])
      refute perform_auto_provision host, r1
      assert_equal "xabc", host.name
    end

  end

end
