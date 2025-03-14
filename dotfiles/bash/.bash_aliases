#!/bin/bash

function launch() {

    launch_type=$1
    launch_option=$2
    launch_sub_option=$3
    case $launch_type in
        fix)
            case $launch_option in
                automation)
                    __fix_automation_containers
                    ;;
                monitors)
                    __fix_monitors
                    ;;
            esac
            ;;
        docker)
            sudo systemctl start docker

            case $launch_option in
                abb)
                    local container_name=mysql-abb
                    if __missing_docker_container $container_name; then
                        __docker_run_abb
                    else
                        docker start $container_name
                    fi
                    ;;
                swagelok)
                    local container_name=mysql-swagelok
                    if __missing_docker_container $container_name; then
                        __docker_run_swagelok
                    else
                        docker start $container_name
                    fi
                    ;;
                sst)
                    local container_name=mssql-sst
                    if __missing_docker_container $container_name; then
                        __docker_run_sst
                    else
                        docker start $container_name
                    fi
                    ;;
                trek)
                    local container_name=mssql-trek
                    if __missing_docker_container $container_name; then
                        __docker_run_trek
                    else
                        docker start $container_name
                    fi
                    ;;
            esac
            ;;
        tunnel)
            case $launch_option in
                trek)
                    case $launch_sub_option in
                        dev)
                            __tunnel_trek
                            ;;
                        prod)
                            __tunnel_trek_prod
                            ;;
                    esac
                    ;;
            esac
            ;;
    esac
}

function __autocompletion() {
    latest="${COMP_WORDS[$COMP_CWORD]}"
    prev="${COMP_WORDS[$COMP_CWORD - 1]}"
    words=""
    case "${prev}" in
        launch)
            words="fix docker tunnel"
            ;;
        fix)
            words="monitor automation"
            ;;
        docker)
            words="abb swagelok trek sst"
            ;;
        tunnel)
            words="trek"
            ;;
    esac

    if test "tunnel" = "${COMP_WORDS[$COMP_CWORD - 2]}"; then
            case "${prev}" in
                trek)
                    words="dev prod"
                    ;;
        esac
    fi

    COMPREPLY=($(compgen -W "$words" -- $latest))
    return 0
}


# Main

complete -F __autocompletion launch
export -f launch

# Util methods

## Fix

function __fix_automation_containers() {
    docker stop $(docker ps -aq)
    docker rm $(docker ps -aq)
}

function __fix_monitors() {
    xrandr --output eDP1 --mode 1920x1080 \
        --output DP2-1-5 --right-of eDP1 --mode 1920x1200 --primary \
        --output DP2-2 --right-of DP2-1-5 --mode 1920x1200
}

## Docker

function __missing_docker_container() {
    local container_name=$1
    if [ ! "$(docker ps -a -q -f name="$container_name")" ]; then
        if [ "$(docker ps -aq -f status=exited -f name="$container_name")" ]; then
            # cleanup
            docker rm "$container_name"
        fi
        # 0 is exist code, so it means true inside if
        return 0
    fi
    # 1 is exist code, so it means false inside if
    return 1

}

function __docker_run_abb() {
    docker run --ulimit nofile=262144:262144 --name mysql-abb -d -p 3306:3306 -v /home/clutcher/db/mysql8:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=ge -e MYSQL_USER=hybris -e MYSQL_PASSWORD=hybris mysql/mysql-server:8.0
}


function __docker_run_swagelok() {
    docker run --ulimit nofile=262144:262144 --name mysql-swagelok -d -p 3306:3306 -v /home/clutcher/db/mysql:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=swagelock -e MYSQL_USER=hybris -e MYSQL_PASSWORD=Monkey1! mysql/mysql-server:5.7
}

function __docker_run_sst() {
    docker run --name mssql-sst -d -e 'ACCEPT_EULA=Y' -e 'MSSQL_SA_PASSWORD=SAPassw0rd' -p 1433:1433 -v /home/clutcher/db/mssql22/data:/var/opt/mssql/data -v /home/clutcher/db/mssql22/log:/var/opt/mssql/log -v /home/clutcher/db/mssql22/secrets:/var/opt/mssql/secrets mcr.microsoft.com/mssql/server:2022-latest
}

function __docker_run_trek() {
    docker run --name mssql-trek -d -e 'ACCEPT_EULA=Y' -e 'MSSQL_SA_PASSWORD=SApwdForDB1.' -p 1433:1433 -v /home/clutcher/db/mssql/data:/var/opt/mssql/data -v /home/clutcher/db/mssql/log:/var/opt/mssql/log -v /home/clutcher/db/mssql/secrets:/var/opt/mssql/secrets mcr.microsoft.com/mssql/server:2017-latest
}

## Tunnel

function __tunnel_trek() {
    source ~/.trek_aliases
    __trek_update_keys
    trektunnel
}

function __tunnel_trek_prod() {
    source ~/.trek_aliases
    __trek_update_keys
    trektunnel prd
}

function __trek_update_keys() {
    TREKSSHDIR=$HOME/.ssh
    TREKSSHCONFIG=$TREKSSHDIR/aadconfig
    TREKSSHKEYDIR=$TREKSSHDIR/az_ssh_config/*
    rm -rf $TREKSSHCONFIG
    rm -rf $TREKSSHKEYDIR

    azconfig
}
