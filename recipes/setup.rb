include_recipe 'mongodb::10gen_repo'

node.set['build_essential']['compiletime'] = true
include_recipe 'build-essential'

include_recipe 'git'
include_recipe 'nginx'
include_recipe 'user'

user_account node['errbit']['user'] do
  password node['errbit']['password']
  system_user true
  gid 'sudo'
end

group node['errbit']['group'] do
  members node['errbit']['user']
  append true
end

include_recipe 'chruby::system'

# Workaround for default ruby not being set on the first install
ENV['PATH'] = "/opt/rubies/#{node[:chruby][:default]}/bin:#{ENV['PATH']}"

gem_package 'bundler' do
  gem_binary "/opt/rubies/#{node[:chruby][:default]}/bin/gem"
end

secret_token = rand(8**256).to_s(36).ljust(8,'a')[0..150]

# Workaround for secret_token var not being set on the first install
ENV['SECRET_TOKEN'] = secret_token

execute 'set SECRET_TOKEN var' do
  user node['errbit']['user']
  command "echo 'export SECRET_TOKEN=#{secret_token}' >> /home/#{node['errbit']['user']}/.bash_profile"
  not_if "grep SECRET_TOKEN /home/#{node['errbit']['user']}/.bash_profile"
end

execute 'set RAILS_ENV var' do
  user node['errbit']['user']
  command "echo 'export RAILS_ENV=production' >> /home/#{node['errbit']['user']}/.bash_profile"
  not_if "grep RAILS_ENV /home/#{node['errbit']['user']}/.bash_profile"
end

execute 'update sources list' do
  command 'apt-get update'
  action :nothing
end.run_action(:run)

%w(libxml2-dev libxslt1-dev libcurl4-gnutls-dev).each do |pkg|
  r = package pkg do
    action :nothing
  end
  r.run_action(:install)
end

directory node['errbit']['deploy_to'] do
  owner node['errbit']['user']
  group node['errbit']['group']
  action :create
  recursive true
end

directory "#{node['errbit']['deploy_to']}/shared" do
  owner node['errbit']['user']
  group node['errbit']['group']
  mode 00755
end

%w{ log pids system tmp vendor_bundle scripts config sockets }.each do |dir|
  directory "#{node['errbit']['deploy_to']}/shared/#{dir}" do
    owner node['errbit']['user']
    group node['errbit']['group']
    mode 0775
    recursive true
  end
end

# errbit config.yml
template "#{node['errbit']['deploy_to']}/shared/config/config.yml" do
  source 'config.yml.erb'
  owner node['errbit']['user']
  group node['errbit']['group']
  mode 00644
  variables(params: {
    host: node['errbit']['config']['host'],
    enforce_ssl: node['errbit']['config']['enforce_ssl'],
    email_from: node['errbit']['config']['email_from'],
    per_app_email_at_notices: node['errbit']['config']['per_app_email_at_notices'],
    email_at_notices: node['errbit']['config']['email_at_notices'],
    confirm_resolve_err: node['errbit']['config']['confirm_resolve_err'],
    user_has_username: node['errbit']['config']['user_has_username'],
    allow_comments_with_issue_tracker: node['errbit']['config']['allow_comments_with_issue_tracker'],
    use_gravatar: node['errbit']['config']['use_gravatar'],
    gravatar_default: node['errbit']['config']['gravatar_default'],
    github_authentication: node['errbit']['config']['github_authentication'],
    github_client_id: node['errbit']['config']['github_client_id'],
    github_secret: node['errbit']['config']['github_secret'],
    github_access_scope: node['errbit']['config']['github_access_scope']
  })
end

template "#{node['errbit']['deploy_to']}/shared/config/mongoid.yml" do
  source 'mongoid.yml.erb'
  owner node['errbit']['user']
  group node['errbit']['group']
  mode 00644
  variables( params: {
    environment: node['errbit']['environment'],
    host: node['errbit']['db']['host'],
    port: node['errbit']['db']['port'],
    database: node['errbit']['db']['database']
  })
end

deploy_revision node['errbit']['deploy_to'] do
  repo node['errbit']['repo_url']
  revision node['errbit']['revision']
  user node['errbit']['user']
  group node['errbit']['group']
  enable_submodules false
  migrate false

  before_migrate do
    link "#{release_path}/vendor/bundle" do
      to "#{node['errbit']['deploy_to']}/shared/vendor_bundle"
    end

    execute 'bundle install --deployment' do
      ignore_failure true
      cwd release_path
    end
  end

  symlink_before_migrate nil
  symlinks(
    'config/config.yml' => 'config/config.yml',
    'config/mongoid.yml' => 'config/mongoid.yml'
  )

  environment 'RAILS_ENV' => node['errbit']['environment']
  shallow_clone true

  before_restart do
    Chef::Log.info '*' * 20 + 'COMPILING ASSETS' + '*' * 20

    execute 'asset_precompile' do
      cwd release_path
      user node['errbit']['user']
      group node['errbit']['group']
      command 'bundle exec rake assets:precompile --trace'
      environment ({'RAILS_ENV' => node['errbit']['environment']})
    end
  end

  scm_provider Chef::Provider::Git
end

execute 'bootstrap admin user' do
  command 'bundle exec rake db:seed -t'
  cwd "#{node['errbit']['deploy_to']}/current"
  environment ({'RAILS_ENV' => 'production'})
  not_if "bundle exec rails runner 'p User.where(admin: true).first'"
end

template "#{node['nginx']['dir']}/sites-available/#{node['errbit']['name']}" do
  source 'nginx.conf.erb'
  owner 'root'
  group 'root'
  mode 00644
end

nginx_site node['errbit']['name'] do
  enable true
end
