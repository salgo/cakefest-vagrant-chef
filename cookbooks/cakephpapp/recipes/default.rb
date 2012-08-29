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

include_recipe "mysql::ruby"
include_recipe "apt"
include_recipe "build-essential"
include_recipe "apache2"
include_recipe "mysql::server"
include_recipe "php"
include_recipe "php::module_mysql"
include_recipe "apache2::mod_php5"

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

# Save node data after writing the MySQL root password, so that a failed chef-client
# run that gets this far doesn't cause an unknown password to get applied to the box
# without being saved in the node data.

unless Chef::Config[:solo]
  ruby_block "save node data" do
    block do
      node.save
    end
    action :create
  end
end