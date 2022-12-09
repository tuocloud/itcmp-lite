#!/usr/bin/env bash

function logging(){
	local_date=$(date +"%H:%M:%S")
	logger -t $0 $1
	echo "[ $USER $local_date ]: $1" | tee -a ${log_path}
}

log_path="/var/log/cmp-install.log"
dockerPath="/opt/docker"
dockerConfigFolder="/etc/docker"
dockerConfigFile="$dockerConfigFolder/daemon.json"

red=31
blue=34
green=32
yellow=33
validationPassed=1

function pre_check(){
    if [[ ! -f $CMP_TAR_PAK  ]];then
        echo "Installation package not found: $CMP_TAR_PAK"
        exit 1
    fi
}

function set_timezone(){
   # timedatectl set-timezone Asia/Shanghai
    hostnamectl set-hostname cmp --static
    echo "*/5 * * * * su -c 'free -m && sync && echo 3 > /proc/sys/vm/drop_caches && sync && free -m'" >> /var/spool/cron/root
}

function printTitle()
{
  echo -e "\n\n**********\t ${1} \t**********\n"
}

function printSubTitle()
{
  echo -e "------\t \033[${blue}m ${1} \033[0m \t------\n"
}


function colorMsg()
{
  echo -e "\033[$1m $2 \033[0m"
}

# 获取宿主机IP
function get_pubip(){
    echo "Get public IP address"
    PUBIP=`/sbin/ip add | grep 'inet '| grep -v '127.0.0.1' | cut -d/ -f1 | awk '{ print $2}' | head -n1`
    echo "Public IP Address: $PUBIP"
}

function config_firewall(){
## CMP 开放防火墙端口 
systemctl stop firewalld
systemctl disable firewalld
sed -i '/SELINUX/{s/permissive/disabled/}' /etc/selinux/config
setenforce 0
#firewall-cmd --zone=public --add-port=443/tcp --permanent
#firewall-cmd --reload
}


# 解压部署包,配置文件
function untar_pak(){
   # echo ">> Begin to unpack"
    printf ">> Begin to unpack      %-45s ........................ " $temp_file
    tar -zxvf $CMP_TAR_PAK -C /var/  >>${log_path}
    printf "\e[32m[OK]\e[0m \n"
    printf ">> Modify configuration %-45s ........................ " $temp_file 
    cp -rvp /var/iTCMP/standalone/conf /opt/conf >>${log_path}
    cp -rvp /var/iTCMP/product/cmp /opt/cmp >>${log_path}
    cp -rvp /var/iTCMP/product/sql /opt/sql >>${log_path}
    cp -rvp /var/iTCMP/standalone/docker-compose.yml /opt/ >>${log_path}
    tar -zxvf /var/iTCMP/product/cmp-ui.tar.gz -C /opt/ >>${log_path}
    #echo ">> End of unpack"
    sed -i "s/127.0.0.1/${PUBIP}/g" /opt/conf/nginx.conf
    sed -i "s/127.0.0.1/${PUBIP}/g" /opt/cmp/application.yml
    printf "\e[32m[OK]\e[0m \n"
}

function pre_install(){
    set_timezone
    config_firewall
    get_pubip
    untar_pak
}



systemName="iTCMP-Lite 云管平台 1.0"

colorMsg $yellow "\n\n开始安装 $systemName，版本 - $versionInfo"

printTitle "${systemName} 安装环境检测"

# root用户检测
echo -ne "root 用户检测 \t\t........................ "
isRoot=`id -u -n | grep root | wc -l`
if [ "x$isRoot" == "x1" ];then
  colorMsg $green "[OK]"
else
  colorMsg $red "[ERROR] 请用 root 用户执行安装脚本"
  validationPassed=0
fi

# CPU内核数检测
echo -ne "CPU检测 \t\t........................ "
processor=`cat /proc/cpuinfo| grep "processor"| wc -l`
if [ $processor -lt 4 ];then
  colorMsg $red "[ERROR] CPU 小于 4核，CMP 所在机器的 CPU 需要至少 4核"
  validationPassed=0
else
  colorMsg $green "[OK]"
fi


# 内存大小检测
echo -ne "内存检测 \t\t........................ "
memTotal=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
if [ $memTotal -lt 8000000 ];then
  colorMsg $red "[ERROR] 内存小于 8G，CMP 所在机器的内存需要至少 8G"
  validationPassed=0
else
  colorMsg $green "[OK]"
fi


# 磁盘剩余空间检测
echo -ne "磁盘剩余空间检测 \t........................ "
path="/opt"

IFSOld=$IFS
IFS=$'\n'
lines=$(df)
for line in ${lines};do
  linePath=`echo ${line} | awk -F' ' '{print $6}'`
  lineAvail=`echo ${line} | awk -F' ' '{print $4}'`
  if [ "${linePath:0:1}" != "/" ]; then
    continue
  fi
  
  if [ "${linePath}" == "/" ]; then
    rootAvail=${lineAvail}
    continue
  fi
  
  pathLength=${#path}
  if [ "${linePath:0:${pathLength}}" == "${path}" ]; then
    pathAvail=${lineAvail}
    break
  fi
done
IFS=$IFSOld

if test -z "${pathAvail}"
then
  pathAvail=${rootAvail}
fi

if [ $pathAvail -lt 100000 ]; then
#if [ $pathAvail -lt 100000000 ]; then
  colorMsg $red "[ERROR] 安装目录剩余空间小于 100G，CMP 所在机器的安装目录可用空间需要至少 100G"
  validationPassed=0
else
  colorMsg $green "[OK]"
fi


# docker环境检测
echo -ne "Docker 检测 \t\t........................ "
hasDocker=`which docker 2>&1`
if [[ "${hasDocker}" =~ "no docker" ]]; then
  colorMsg $green '[OK]'
else
  dockerVersion=`docker info | grep 'Server Version' | awk -F: '{print $2}' | awk -F. '{print $1}'`
  if [ "$dockerVersion" -lt "18" ];then
    colorMsg $red "[ERROR] Docker 版本需要 18 以上"
    validationPassed=0
  else
    colorMsg $green "[OK]"

    echo -ne "docker-compose 检测 \t........................ "
    hasDockerCompose=`which docker-compose 2>&1`
    if [[ "${hasDockerCompose}" =~ "no docker-compose" ]]; then
      colorMsg $red "[ERROR] 未安装 docker-compose"
      validationPassed=0
    else
      colorMsg $green '[OK]'
    fi
  fi
fi 


if [ $validationPassed -eq 0 ]; then
  colorMsg $red "\n${systemName} 安装环境检测未通过，请查阅上述环境检测结果\n"
  exit 1
fi

printTitle "开始进行${systemName} 安装"

# 操作历史显示时间
echo "HISTFILESIZE=2000" >> /etc/bashrc && echo "HISTSIZE=2000" >> /etc/bashrc && echo 'HISTTIMEFORMAT="%Y%m%d %T "'>> /etc/bashrc && export HISTTIMEFORMAT

function CMP_install(){

# step 1 - install docker & docker-compose
printSubTitle "安装 Docker 运行时环境"
if [[ "${hasDocker}" =~ "no docker" ]]; then

  if [ ! -f "$dockerConfigFile" ];then
    echo "修改 docker 存储目录到 $dockerPath"

    if [ ! -d "$dockerPath" ];then
      mkdir -p "$dockerPath"
    fi

    if [ ! -d "$dockerConfigFolder" ];then
      mkdir -p "$dockerConfigFolder"
    fi

 cat >$dockerConfigFile<<EOF
 {
    "graph": "$dockerPath"
   }
EOF
  fi

  cp -rvp /var/iTCMP/docker/bin/* /usr/bin/ >>${log_path}
  cp -rvp /var/iTCMP/docker/service/docker.service /etc/systemd/system/ >>${log_path}
  chmod +x /usr/bin/docker*
  chmod 754 /etc/systemd/system/docker.service
  echo -ne "Docker \t\t\t........................ "
  colorMsg $green "[OK]" 
else
  echo -ne "Docker \t\t\t........................ "
  colorMsg $green "[OK] 已安装 Docker !!，忽略安装" 
fi
systemctl daemon-reload && systemctl start docker.service >> $log_path 2>&1
systemctl enable docker.service >> $log_path 2>&1
echo -ne "启动 Docker 服务 \t........................ "
colorMsg $green "[OK]" 

if [ `grep "vm.max_map_count" /etc/sysctl.conf | wc -l` -eq 0 ];then
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  sysctl -p /etc/sysctl.conf >> $log_path
fi

chmod +x /etc/rc.d/rc.local
systemctl restart docker.service
colorMsg $green "[OK]"
cd /opt/
docker-compose up -d  --build

printf "\e[32m[OK]\e[0m \n"

printTitle "启动 iTCMP-Lite 服务"
echo -ne "启动 iTCMP-Lite 服务 \t........................ " 

echo
echo "*********************************************************************************************************************************"
echo -e "\t${systemName} 安装完成，请在服务完全启动后(由于机器性能差异大概需要等待5分钟左右)访问 https://${PUBIP} 来访问 CMP 云管平台"
echo
echo -e "\t系统管理员初始登录信息："
echo -ne "\t    用户名："
colorMsg $yellow "\tadmin"
echo -ne "\t    密码："
colorMsg $yellow "\ttuocloud.cn"
echo 
echo "*********************************************************************************************************************************"
echo
}
function deploy(){

    echo ">> Begin to deploy iTCMP-Lite 1.0: $CMP_TAR_PAK"
    pre_check
    pre_install
    CMP_install
    echo ">> End of deploy iTCMP-Lite 1.0: $CMP_TAR_PAK"
}



function usage(){
    echo "Usage:   bash deployiTCMP-Lite.sh -f <CMP_PAK>"
}

# clear package
rm -rf /var/CMP

arg=$(getopt  -o f:h help $@)
while true
do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -f)
            if [[ $# -ne 2 ]];then
                usage
                exit 1
            fi
            CMP_TAR_PAK=$2
            deploy
            exit 0
            ;;
        *)
            usage
            exit 0
    esac
done
