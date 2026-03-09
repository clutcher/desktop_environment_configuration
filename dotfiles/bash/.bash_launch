#!/bin/bash

function launch() {

    launch_type=$1
    launch_option=$2
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
                iba)
                    local container_name=mssql-iba
                    if __missing_docker_container $container_name; then
                        __docker_run_iba
                    else
                        docker start $container_name
                    fi
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
            words="fix docker"
            ;;
        fix)
            words="monitor automation"
            ;;
        docker)
            words="abb iba"
            ;;
    esac

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

function __docker_run_iba() {
    docker run --name mssql-iba -d -e 'ACCEPT_EULA=Y' -e 'MSSQL_SA_PASSWORD=Hybris1!' -p 1433:1433 -v /home/clutcher/db/mssql17/data:/var/opt/mssql/data -v /home/clutcher/db/mssql17/log:/var/opt/mssql/log -v /home/clutcher/db/mssql17/secrets:/var/opt/mssql/secrets mcr.microsoft.com/mssql/server:2017-latest
}
