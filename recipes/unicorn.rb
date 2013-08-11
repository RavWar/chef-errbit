include_recipe 'unicorn'

Chef::Log.info "-" * 70
Chef::Log.info "Unicorn Config"

template "#{node['errbit']['deploy_to']}/shared/config/unicorn.conf" do
  source "unicorn.conf.erb"
  owner node['errbit']['user']
  group node['errbit']['group']
  mode 00644
end

template "/etc/init.d/unicorn_#{node['errbit']['name']}" do
  source "unicorn.service.erb"
  owner "root"
  group "root"
  mode 00755
end

service "unicorn_#{node['errbit']['name']}" do
  provider Chef::Provider::Service::Init::Debian
  start_command   "/etc/init.d/unicorn_#{node['errbit']['name']} start"
  stop_command    "/etc/init.d/unicorn_#{node['errbit']['name']} stop"
  restart_command "/etc/init.d/unicorn_#{node['errbit']['name']} restart"
  status_command  "/etc/init.d/unicorn_#{node['errbit']['name']} status"
  supports :start => true, :stop => true, :restart => true, :status => true
  action :nothing
end

# Restarting the unicorn
service "unicorn_#{node['errbit']['name']}" do
  action :restart
end
