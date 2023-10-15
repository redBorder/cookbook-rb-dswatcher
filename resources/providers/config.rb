
# Cookbook Name:: rbdswatcher
#
# Provider:: config
#

include Rbdswatcher::Helper

action :add do
  begin

    user = new_resource.user
    cdomain = new_resource.cdomain

    dnf_package "redborder-dswatcher" do
      action :upgrade
      flush_cache [:before]
    end

    execute "create_user" do
      command "/usr/sbin/useradd -r #{user}"
      ignore_failure true
      not_if "getent passwd #{user}"
    end

    flow_nodes = []

    %w[ /etc/redborder-dswatcher].each do |path|
      directory path do
        owner user
        group user
        mode 0755
        action :create
      end
    end

    template "/etc/redborder-dswatcher/config.yml" do
      source "config.yml.erb"
      owner user
      group user
      mode 0644
      ignore_failure true
      cookbook "rbdswatcher"
      variables(:user => user)
      notifies :restart, "service[redborder-dswatcher]", :delayed
    end

    # TODO: Use Chef::EncryptedDataBagItem.load instead
    root_pem = Chef::EncryptedDataBagItem.load("certs", "root") rescue root_pem = nil

    if !root_pem.nil? and !root_pem["private_rsa"].nil?
      template "/etc/redborder-dswatcher/admin.pem" do
        source "rsa_cert.pem.erb"
        owner user
        group user
        mode 0600
        retries 2
        variables(:private_rsa => root_pem["private_rsa"])
        cookbook "rbdswatcher"
      end
    end


    service "redborder-dswatcher" do
      service_name "redborder-dswatcher"
      ignore_failure true
      supports :status => true, :restart => true, :enable => true
      action [:start, :enable]
    end

    Chef::Log.info("Redborder-Dswatcher cookbook has been processed")
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    
    service "redborder-dswatcher" do
      service_name "redborder-dswatcher"
      ignore_failure true
      supports :status => true, :enable => true
      action [:stop, :disable]
    end

    %w[ /etc/redborder-dswatcher ].each do |path|
      directory path do
        recursive true
        action :delete
      end
    end

    dnf_package "redborder-dswatcher" do
      action :remove
    end

    Chef::Log.info("Redborder-Dswatcher cookbook has been processed")
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :register do
  begin
    if !node["redborder-dswatcher"]["registered"]
      query = {}
      query["ID"] = "redborder-dswatcher-#{node["hostname"]}"
      query["Name"] = "redborder-dswatcher"
      query["Address"] = "#{node["ipaddress"]}"
      query["Port"] = "5000"
      json_query = Chef::JSONCompat.to_json(query)

      execute 'Register service in consul' do
         command "curl http://localhost:8500/v1/agent/service/register -d '#{json_query}' &>/dev/null"
         action :nothing
      end.run_action(:run)

      node.default["redborder-dswatcher"]["registered"] = true
      Chef::Log.info("redborder-Dswatcher service has been registered to consul")
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :deregister do
  begin
    if node["redborder-dswatcher"]["registered"]
      execute 'Deregister service in consul' do
        command "curl http://localhost:8500/v1/agent/service/deregister/redborder-dswatcher-#{node["hostname"]} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.default["redborder-dswatcher"]["registered"] = false
      Chef::Log.info("redborder-Dswatcher service has been deregistered from consul")
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end
