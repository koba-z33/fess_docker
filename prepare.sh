#!/bin/bash

set -eu

readonly DIR_SCRIPT=$(cd $(dirname $0); pwd)
readonly DIR_ROOT_VOLUMES=${DIR_SCRIPT}/volumes
readonly DIR_GITBUCKET_HOME=${DIR_ROOT_VOLUMES}/gitbucket_data

function _mkdir() {
    local _dir=$1
    if [ -d ${_dir} ]; then
        echo "skip mkdir ${_dir}"
    else
        mkdir -p ${_dir}
        echo "mkdir ${_dir}"
    fi
}

function _start_operation()
{
cat << EOF

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ $*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
}



function _mk_volume_all()
{
    _start_operation "make directory for docker"

    _mkdir ${DIR_ROOT_VOLUMES}/fess_data
    _mkdir ${DIR_ROOT_VOLUMES}/elasticsearch_data
}

function _print_usage()
{
cat << EOF
------------------------------------------------------------
- usage
- $0 <context name> <fess post>
- 
- http://<host name>/<context name>/fess/
------------------------------------------------------------
EOF
}

function _mk_conf()
{
    if [ -f ${DIR_SCRIPT}/.env ]; then
        echo "already exist .env"
        return 0
    fi

    if [ $# -lt 2 ]; then
        _print_usage $*
        exit 1
    fi

    _start_operation "make .env for docker-compose and conf for nginx"

    local _context_path=$1
    local _fess_port=$2

    local _dir_conf=${DIR_SCRIPT}/conf
    local _dir_nginx_conf=${_dir_conf}/nginx
    local _file_docker_compose_env=${_dir_conf}/docker_compose.env
    local _file_fess_nginx_conf=${_dir_nginx_conf}/${_fess_port}_${_context_path}_fess.conf

    echo ${_dir_nginx_conf}
    _mkdir ${_dir_nginx_conf}

cat << EOF > ${_file_docker_compose_env}
# fess port
FESS_PORT=${_fess_port}

# fess context pass
FESS_CONTEXT_PATH=${_context_path}/fess
EOF

ln -sf conf/docker_compose.env ${DIR_SCRIPT}/.env

cat << EOF > ${_file_fess_nginx_conf}
location /${_context_path}/fess/ {
    proxy_pass              http://127.0.0.1:${_fess_port}/${_context_path}/fess/;
    proxy_set_header        Host \$host;
    proxy_set_header        X-Real-IP \$remote_addr;
    proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_connect_timeout   150;
    proxy_send_timeout      100;
    proxy_read_timeout      100;
    proxy_buffers           4 32k;
    client_max_body_size    500m; # Big number is we can post big commits.
    client_body_buffer_size 128k;
}
EOF
}

function _check_map_count()
{
    local _value=$(cat /proc/sys/vm/max_map_count)

    if [ ${_value} -ge 262144 ]; then
        return 0
    fi
cat << EOI
------------------------------------------------------------
max_map_count = ${_value}
max_map_count is bigger than 262144 for elasticsearch.
 
sudo sh -eux <<EOF
echo "vm.max_map_count=262144" > /etc/sysctl.d/elasticsearch.conf
sysctl -w vm.max_map_count=262144
EOF
------------------------------------------------------------
EOI
    exit 1
}

_mk_conf $*

_check_map_count

_mk_volume_all
