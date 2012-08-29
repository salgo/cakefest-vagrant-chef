#
# Cookbook Name:: cakephpapp
# Recipe:: default
#
# Copyright 2009-2010, Opscode, Inc.
# Copyright 2012, Andy Gale
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

###############################################################################
# Get all this stuff installed for free
###############################################################################

include_recipe "mysql::ruby"
include_recipe "apt"
include_recipe "build-essential"
include_recipe "apache2"
include_recipe "mysql::server"
include_recipe "php"
include_recipe "php::module_mysql"
include_recipe "apache2::mod_php5"

###############################################################################
# Create our app database and make a MySQL user and grant them permisions
###############################################################################

execute "mysql-install-cakephpapp-privileges" do
  command "/usr/bin/mysql -u root -p\"#{node['mysql']['server_root_password']}\" < #{node['mysql']['conf_dir']}/cakephpapp-grants.sql"
  action :nothing
end

template "#{node['mysql']['conf_dir']}/cakephpapp-grants.sql" do
  source "grants.sql.erb"
  owner "root"
  group "root"
  mode "0600"
  variables(
    :user     => node['cakephpapp']['db']['user'],
    :password => node['cakephpapp']['db']['password'],
    :database => node['cakephpapp']['db']['database']
  )
  notifies :run, "execute[mysql-install-cakephpapp-privileges]", :immediately
end

execute "create #{node['cakephpapp']['db']['database']} database" do
  command "/usr/bin/mysqladmin -u root -p\"#{node['mysql']['server_root_password']}\" create #{node['cakephpapp']['db']['database']}"
  not_if do
    require 'mysql'
    m = Mysql.new("localhost", "root", node['mysql']['server_root_password'])
    m.list_dbs.include?(node['cakephpapp']['db']['database'])
  end
  notifies :create, "ruby_block[save node data]", :immediately unless Chef::Config[:solo]
end

###############################################################################
# Save node data after writing the MySQL root password, so that a failed
# chef-client run that gets this far doesn't cause an unknown password to get
# applied to the box without being saved in the node data.
#
# Not used in Vagrant and chef-solo but vital when running Chef in
# client/server mode
###############################################################################

unless Chef::Config[:solo]
  ruby_block "save node data" do
    block do
      node.save
    end
    action :create
  end
end

###############################################################################
# The following section fetches a base install of CakePHP. You probably won't
# want to do this as part of your Chef/Vagrant/CakePHP setup but it serves a
# neat purpose in our example                                           
# 
# You code should be in your repo along with the Chef and Vagrant stuff in
# the cakephpapp directory
###############################################################################

remote_file "#{Chef::Config[:file_cache_path]}/cakephpapp.tar.gz" do
  source "https://github.com/cakephp/cakephp/tarball/2.2.1"
  mode "0644"
end

directory "#{node['cakephpapp']['dir']}" do
  owner node['cakephpapp']['user']
  group node['cakephpapp']['group']
  mode "0775"
  action :create
end

execute "untar-cakephp" do
  cwd node['cakephpapp']['dir']
  command "tar --strip-components 1 -xzf #{Chef::Config[:file_cache_path]}/cakephpapp.tar.gz"
  creates "#{node['cakephpapp']['dir']}/index.php"
end

###############################################################################
# That's the end of the fetch cakephp bit. Carry on as usual.
###############################################################################

###############################################################################
# Ensure our tmp directories are owned and writable by the correct users
# (this doesn't work for vagrant share directories)
###############################################################################

tmp = node['cakephpapp']['dir']
[ tmp + '/app/tmp', 
  tmp + '/app/tmp/cache',
  tmp + '/app/tmp/cache/models', 
  tmp + '/app/tmp/cache/persistent',
  tmp + '/app/tmp/cache/views',
  tmp + '/app/tmp/logs',
  tmp + '/app/tmp/sessions',
  tmp + '/app/tmp/tests' ].each do |dir|
    directory dir do
      owner node['cakephpapp']['user']
      group node['cakephpapp']['group']
      mode "0777"
      action :create
    end
end

###############################################################################
# Setup database config - owned by root because we want to keep this under our
# control and manage it with chef
###############################################################################

template node['cakephpapp']['dir'] + '/app/Config/database.php' do
  source "database.php.erb"
  mode 0755
  owner "root"
  group "root"
  variables(
    :database        => node['cakephpapp']['db']['database'],
    :user            => node['cakephpapp']['db']['user'],
    :password        => node['cakephpapp']['db']['password']
  )
end

###############################################################################
# Setup core.php config - owned by root because we want to keep this under our
# control and manage it with chef
###############################################################################

template node['cakephpapp']['dir'] + '/app/Config/core.php' do
  source "core.php.erb"
  mode 0755
  owner "root"
  group "root"
end

###############################################################################
# Disable default "It works" Apache site.
###############################################################################

apache_site "000-default" do
  enable false
end

###############################################################################
# Setup virtualhost for our CakePHP app
###############################################################################

web_app "cakephpapp" do
  template "cakephpapp.conf.erb"
  docroot "#{node['cakephpapp']['dir']}"
  server_name "#{node['cakephpapp']['host']}"
end

