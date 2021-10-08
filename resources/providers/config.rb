
# Cookbook Name:: dswatcher
#
# Provider:: config
#

include Dswatcher::Helper

action :add do
  begin

    user = new_resource.user
    cdomain = new_resource.cdomain

    yum_package "dswatcher" do
      action :upgrade
      flush_cache [:before]
    end

    user user do
      action :create
      system true
    end

    flow_nodes = []

    %w[ /etc/dswatcher].each do |path|
      directory path do
        owner user
        group user
        mode 0755
        action :create
      end
    end

    template "/etc/dswatcher/config.yml" do
      source "config.yml.erb"
      owner user
      group user
      mode 0644
      ignore_failure true
      cookbook "dswatcher"
      variables(:user => user)
      notifies :restart, "service[dswatcher]", :delayed
    end

    # TODO: Use Chef::EncryptedDataBagItem.load instead
    root_pem = Chef::DataBagItem.load("certs", "root_pem") rescue root_pem = nil

    if !root_pem.nil? and !root_pem["private_rsa"].nil?
      template "/etc/dswatcher/admin.pem" do
        source "rsa_cert.pem.erb"
        owner user
        group user
        mode 0600
        retries 2
        variables(:private_rsa => root_pem["private_rsa"])
      end
    end


    service "dswatcher" do
      service_name "dswatcher"
      ignore_failure true
      supports :status => true, :reload => true, :restart => true, :enable => true
      action [:start, :enable]
    end

    Chef::Log.info("Dswatcher cookbook has been processed")
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    
    service "dswatcher" do
      service_name "dswatcher"
      ignore_failure true
      supports :status => true, :enable => true
      action [:stop, :disable]
    end

    %w[ /etc/dswatcher ].each do |path|
      directory path do
        recursive true
        action :delete
      end
    end

    yum_package "dswatcher" do
      action :remove
    end

    Chef::Log.info("Dswatcher cookbook has been processed")
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :register do
  begin
    if !node["dswatcher"]["registered"]
      query = {}
      query["ID"] = "dswatcher-#{node["hostname"]}"
      query["Name"] = "dswatcher"
      query["Address"] = "#{node["ipaddress"]}"
      query["Port"] = "5000"
      json_query = Chef::JSONCompat.to_json(query)

      execute 'Register service in consul' do
         command "curl http://localhost:8500/v1/agent/service/register -d '#{json_query}' &>/dev/null"
         action :nothing
      end.run_action(:run)

      node.set["dswatcher"]["registered"] = true
      Chef::Log.info("Dswatcher service has been registered to consul")
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :deregister do
  begin
    if node["dswatcher"]["registered"]
      execute 'Deregister service in consul' do
        command "curl http://localhost:8500/v1/agent/service/deregister/dswatcher-#{node["hostname"]} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.set["dswatcher"]["registered"] = false
      Chef::Log.info("Dswatcher service has been deregistered from consul")
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end
