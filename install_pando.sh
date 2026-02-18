#!/usr/bin/env bash
CLUSTERID=`hostname`
K3S_CLUSTER_CIDR="10.1.0.0/24"
K3S_SERVICE_CIDR="10.1.1.0/24"
K3S_OPTIONS="--disable=traefik"
GENERATE_CLUSTER_CIDR=true
GENERATE_SERVICE_CIDR=true
GATEWAY=false
UNINSTALL=false

confirm() {
    if [[ -n "$CONFIRM" ]]; then
        return 0
    fi

    while true; do
        read -r -p "$1? (y/n): " answer < /dev/tty

        case "${answer,,}" in
            y|yes)
                echo "Confirmed. Continuing..."
                return 0
                ;;
            n|no)
                echo "Cancelled."
                return 1
                ;;
            *)
                echo "Please enter y or n."
                ;;
        esac
    done
}

# Convert CIDRs to sortable numeric form
cidr_to_int() {
  local ip="${1%/*}"
  IFS='.' read -r a b c d <<< "$ip"
  echo $(( a * 256 * 256 * 256 + b * 256 * 256 + c * 256 + d ))
}

# Checks that the given CIDR range is not currently in use
#  @cidr The CIDR range to check
#  @clusters The clusters data to check from
#  @returns `false` if the given CIDR range is not found in the cluster, otherwise `true`.
check_cidr() {
    local CIDR="${1%/*}"
    local IN_USE=$(echo "$2" | jq -r '.items[].spec.cluster_cidr[]?, .items[].spec.service_cidr[]?');

    if [[ "$IN_USE" == *"$CIDR"* ]]; then
        return 0
    else
        return 1
    fi
}

# Returns the next CIDR range from the given list
get_next_cidr() {
    local DESIRED_CIDR="$2"
    local DESIRED_PREFIX="${2#*/}"

    # Sort numerically
    local CIDRS=$(echo "$1" | while read -r cidr; do
        printf "%s %s\n" "$(cidr_to_int "$cidr")" "$cidr"
    done | sort -n | awk '{print $2}')

    # Retrieve last CIDR from sorted list
    local LAST_CIDR=$(echo "$CIDRS" | tail -n1)
    LAST_CIDR="${LAST_CIDR:-$DESIRED_CIDR}"
    local PREFIX="${LAST_CIDR#*/}"
    local BASE="${LAST_CIDR%/*}"
    read a b c d <<< "${BASE//./ }"
    local NEW="$2"

    # Increment the network portion based on prefix
    case "$PREFIX" in
    24)
        # Increment the third octet
        c=$((c + 1))
        if [ $b -gt 255 ]; then
            b=$((b + 1 ))
            c=0
            if [ $b -gt 255 ]; then
                echo "No more available CIDR range."
                exit 1
            fi
        fi
        NEW="$a.$b.$c.0/$DESIRED_PREFIX"
        ;;
    16)
        # Increment the second octet
        b=$((b + 1))
        if [ $b -gt 255 ]; then
            echo "No more available CIDR range."
            exit 1
        fi
        NEW="$a.$b.0.0/$DESIRED_PREFIX"
        ;;
    *)
        echo "Unsupported prefix: /$PREFIX"
        exit 1
        ;;
    esac

    echo $NEW
}

# Removes everything that a previous run installed
uninstall() {
  echo "Removing k3s..."
  sudo /usr/local/bin/k3s-uninstall.sh
  echo "Removing subctl..."
  rm ~/.local/bin/subctl
  rm -rf ~/.pando
  echo "Uninstall complete!"
}

GETOPT=$(getopt -o g,o,u,y,h --long confirm,clusterid:,cluster-cidr:,service-cidr:,k3s-options:,gateway,uninstall,help -- "$@")
eval set -- "$GETOPT"
while true
do
    case "$1" in
        -y | --confirm) CONFIRM="true"; shift;;
        --clusterid) CLUSTERID="$2"; shift 2;;
        --cluster-cidr) K3S_CLUSTER_CIDR="$2"; GENERATE_CLUSTER_CIDR=false; shift 2;;
        --service-cidr) K3S_SERVICE_CIDR="$2"; GENERATE_SERVICE_CIDR=false; shift 2;;
        --k3s-options) K3S_OPTIONS+=" $2"; shift 2;;
        -g | --gateway) GATEWAY=true; shift;;
        --uninstall) UNINSTALL=true; shift;;
        -h | --help)
          echo "This script installs PandoNet and configures the machine as a worker node on the network."

          echo "Usage:"
          echo -e "\t-y, --confirm\t\tAutomatically proceed with installation."
          echo -e "\t--clusterid <name>\t\tThe unique name of the machine to register to PandoNet. Defaults to `hostname`"
          echo -e "\t--cluster-cidr <cidr>\t\tThe unique CIDR range of the k3s cluster to use. If not set an CIDR will be automatically assigned based upon network available."
          echo -e "\t--service-cidr <cidr>\t\tThe unique CIDR range of the k3s cluster to use. If not set an CIDR will be automatically assigned based upon network available."
          echo -e "\t-o --k3s-option <option>\t\tThe list of options to pass to k3s. Defaults to `--disable=traefik`"
          echo -e "\t-g --gateway\t\tMarks this machine as a gateway/proxy on the network. Requires a public static IP address."
          echo -e "\t-u --uninstall\t\tUninstalls all PandoNet software and configuration."
          exit 1
          ;;
        ?)
          echo "Invalid option: -${OPTARG}."
          exit 1
          ;;
        --) shift; break;;
        *) break;;
    esac
done

if [ "$UNINSTALL" = "true" ]; then
    uninstall
    exit 0
fi

# Create the broker-info.subm file needed to join PandoNet
mkdir -p ~/.pando
cat <<'EOF' > ~/.pando/broker-info.subm
ewogICJicm9rZXJVUkwiOiAiaHR0cHM6Ly81NC4xODMuMjA0LjE2Njo2NDQzIiwKICAiY2xpZW50
VG9rZW4iOiB7CiAgICAibWV0YWRhdGEiOiB7CiAgICAgICJuYW1lIjogInN1Ym1hcmluZXItazhz
LWJyb2tlci1hZG1pbi10b2tlbi10dm05YyIsCiAgICAgICJnZW5lcmF0ZU5hbWUiOiAic3VibWFy
aW5lci1rOHMtYnJva2VyLWFkbWluLXRva2VuLSIsCiAgICAgICJuYW1lc3BhY2UiOiAic3VibWFy
aW5lci1rOHMtYnJva2VyIiwKICAgICAgInVpZCI6ICI5YWMxNDAwYy1kNGE5LTQ1MDgtOTc3ZS1m
MWExMjQ0ZTJmYzkiLAogICAgICAicmVzb3VyY2VWZXJzaW9uIjogIjQxOTIxMSIsCiAgICAgICJj
cmVhdGlvblRpbWVzdGFtcCI6ICIyMDI2LTAyLTE3VDE5OjUzOjU1WiIsCiAgICAgICJhbm5vdGF0
aW9ucyI6IHsKICAgICAgICAia3ViZXJuZXRlcy5pby9jcmVhdGVkLWJ5IjogInN1YmN0bCIsCiAg
ICAgICAgImt1YmVybmV0ZXMuaW8vc2VydmljZS1hY2NvdW50Lm5hbWUiOiAic3VibWFyaW5lci1r
OHMtYnJva2VyLWFkbWluIiwKICAgICAgICAia3ViZXJuZXRlcy5pby9zZXJ2aWNlLWFjY291bnQu
dWlkIjogIjliNzE5YTdhLWI3ZTYtNDNhNi1iMjg5LTI5MTNiNzI1Y2ViOSIKICAgICAgfSwKICAg
ICAgIm1hbmFnZWRGaWVsZHMiOiBbCiAgICAgICAgewogICAgICAgICAgIm1hbmFnZXIiOiAiazNz
IiwKICAgICAgICAgICJvcGVyYXRpb24iOiAiVXBkYXRlIiwKICAgICAgICAgICJhcGlWZXJzaW9u
IjogInYxIiwKICAgICAgICAgICJ0aW1lIjogIjIwMjYtMDItMTdUMTk6NTM6NTVaIiwKICAgICAg
ICAgICJmaWVsZHNUeXBlIjogIkZpZWxkc1YxIiwKICAgICAgICAgICJmaWVsZHNWMSI6IHsKICAg
ICAgICAgICAgImY6ZGF0YSI6IHsKICAgICAgICAgICAgICAiLiI6IHt9LAogICAgICAgICAgICAg
ICJmOmNhLmNydCI6IHt9LAogICAgICAgICAgICAgICJmOm5hbWVzcGFjZSI6IHt9LAogICAgICAg
ICAgICAgICJmOnRva2VuIjoge30KICAgICAgICAgICAgfSwKICAgICAgICAgICAgImY6bWV0YWRh
dGEiOiB7CiAgICAgICAgICAgICAgImY6YW5ub3RhdGlvbnMiOiB7CiAgICAgICAgICAgICAgICAi
ZjprdWJlcm5ldGVzLmlvL3NlcnZpY2UtYWNjb3VudC51aWQiOiB7fQogICAgICAgICAgICAgIH0K
ICAgICAgICAgICAgfQogICAgICAgICAgfQogICAgICAgIH0sCiAgICAgICAgewogICAgICAgICAg
Im1hbmFnZXIiOiAic3ViY3RsIiwKICAgICAgICAgICJvcGVyYXRpb24iOiAiVXBkYXRlIiwKICAg
ICAgICAgICJhcGlWZXJzaW9uIjogInYxIiwKICAgICAgICAgICJ0aW1lIjogIjIwMjYtMDItMTdU
MTk6NTM6NTVaIiwKICAgICAgICAgICJmaWVsZHNUeXBlIjogIkZpZWxkc1YxIiwKICAgICAgICAg
ICJmaWVsZHNWMSI6IHsKICAgICAgICAgICAgImY6bWV0YWRhdGEiOiB7CiAgICAgICAgICAgICAg
ImY6YW5ub3RhdGlvbnMiOiB7CiAgICAgICAgICAgICAgICAiLiI6IHt9LAogICAgICAgICAgICAg
ICAgImY6a3ViZXJuZXRlcy5pby9jcmVhdGVkLWJ5Ijoge30sCiAgICAgICAgICAgICAgICAiZjpr
dWJlcm5ldGVzLmlvL3NlcnZpY2UtYWNjb3VudC5uYW1lIjoge30KICAgICAgICAgICAgICB9LAog
ICAgICAgICAgICAgICJmOmdlbmVyYXRlTmFtZSI6IHt9CiAgICAgICAgICAgIH0sCiAgICAgICAg
ICAgICJmOnR5cGUiOiB7fQogICAgICAgICAgfQogICAgICAgIH0KICAgICAgXQogICAgfSwKICAg
ICJkYXRhIjogewogICAgICAiY2EuY3J0IjogIkxTMHRMUzFDUlVkSlRpQkRSVkpVU1VaSlEwRlVS
UzB0TFMwdENrMUpTVUpsUkVORFFWSXlaMEYzU1VKQlowbENRVVJCUzBKblozRm9hMnBQVUZGUlJF
RnFRV3BOVTBWM1NIZFpSRlpSVVVSRVFtaHlUVE5OZEdNeVZua0taRzFXZVV4WFRtaFJSRVV6VG5w
Qk5FMTZXVEZQVkUxM1NHaGpUazFxV1hkTmFrVjRUVlJyZDAxNlJYcFhhR05PVFhwWmQwMXFRVFZO
Vkd0M1RYcEZlZ3BYYWtGcVRWTkZkMGgzV1VSV1VWRkVSRUpvY2swelRYUmpNbFo1WkcxV2VVeFhU
bWhSUkVVelRucEJORTE2V1RGUFZFMTNWMVJCVkVKblkzRm9hMnBQQ2xCUlNVSkNaMmR4YUd0cVQx
QlJUVUpDZDA1RFFVRlJRMjV0ZW5NM1ZIcEJUa1JoY3pkeFNuWk9Tek15ZWtjMFFpOHlhM2xhUm5G
dmNrMUJaVEl3WWtJS0sxbHNieklyVTFkTmNqSXZNR3BNZERGS1YyWjFlVEJuV0ZaUWRIUlFZamhS
VkZwYWRuVnRNa3RvYm1sdk1FbDNVVVJCVDBKblRsWklVVGhDUVdZNFJRcENRVTFEUVhGUmQwUjNX
VVJXVWpCVVFWRklMMEpCVlhkQmQwVkNMM3BCWkVKblRsWklVVFJGUm1kUlZXUm9iVlJHVkhkTlNt
VmFTazlESzB0T1ZtOU9DblZ4UkdsVFNEQjNRMmRaU1V0dldrbDZhakJGUVhkSlJGTlJRWGRTWjBs
b1FVeFFNMFJEZVRWR1lrOHlZbmhYZGk5emJXdExPREJoUVcxeFdWTnpXR3dLU0RVMFpVZHpNV2hH
WTNaQlFXbEZRVFJ3VUZaR1pEbFNkR2syTkZsYWNHaHBUMmxCYkhCS1FVY3dNR05GYTBsemNXWk5a
R1pTTW1oWGIxRTlDaTB0TFMwdFJVNUVJRU5GVWxSSlJrbERRVlJGTFMwdExTMEsiLAogICAgICAi
bmFtZXNwYWNlIjogImMzVmliV0Z5YVc1bGNpMXJPSE10WW5KdmEyVnkiLAogICAgICAidG9rZW4i
OiAiWlhsS2FHSkhZMmxQYVVwVFZYcEpNVTVwU1hOSmJYUndXa05KTmtsdVFrZFRSR1J1VGtaUk5G
RnJNVEpTTURWTFZqSTVVR05WY0ROWGEyZ3pWV2t4U0ZFeU5XOVZibVJ0VmtSc1dsSnJjRzFoUlZa
V1ZVYzRhV1pSTG1WNVNuQmpNMDFwVDJsS2NtUlhTbXhqYlRWc1pFZFdla3d6VG14amJscHdXVEpX
YUZreVRuWmtWelV3U1dsM2FXRXpWbWxhV0VwMVdsaFNiR041TlhCaWVUbDZXbGhLTW1GWFRteFpW
MDVxWWpOV2RXUkRPWFZaVnpGc1l6TkNhRmt5VldsUGFVcDZaRmRLZEZsWVNuQmliVlo1VEZkek5H
TjVNV2xqYlRseVdsaEphVXhEU25Ka1YwcHNZMjAxYkdSSFZucE1iV3gyVEROT2JHTnVXbkJaTWxa
b1dUSk9kbVJYTlRCTU0wNXNXVE5LYkdSRE5YVlpWekZzU1dwdmFXTXpWbWxpVjBaNVlWYzFiR05w
TVhKUFNFMTBXVzVLZG1FeVZubE1WMFpyWWxkc2RVeFlVblpoTWxaMVRGaFNNbUpVYkdwSmFYZHBZ
VE5XYVZwWVNuVmFXRkpzWTNrMWNHSjVPWHBhV0VveVlWZE9iRmxYVG1waU0xWjFaRU01ZWxwWVNq
SmhWMDVzVEZkR2Fsa3lPVEZpYmxGMVltMUdkRnBUU1RaSmJrNHhXVzB4YUdOdGJIVmFXRWwwWVhw
b2VreFhTbmxpTW5Sc1kya3hhRnBITVhCaWFVbHpTVzEwTVZsdFZubGliVll3V2xoTmRXRlhPSFpq
TWxaNVpHMXNhbHBYUm1wWk1qa3hZbTVSZG1NeVZubGtiV3hxV2xNeGFGa3lUblprVnpVd1RHNVdj
RnBEU1RaSmFteHBUbnBGTlZsVVpHaE1WMGt6V2xSWmRFNUVUbWhPYVRGcFRXcG5OVXhVU1RWTlZF
NXBUbnBKTVZreVZtbFBVMGx6U1c1T01WbHBTVFpKYms0MVl6TlNiR0pVY0hwYVdFb3lZVmRPYkZs
WFRtcGlNMVoxWkVSd2VtUlhTblJaV0Vwd1ltMVdlVXhYY3pSamVURnBZMjA1Y2xwWVNUWmpNMVpw
WWxkR2VXRlhOV3hqYVRGeVQwaE5kRmx1U25aaE1sWjVURmRHYTJKWGJIVkpiakF1YjFOalVWSm9l
bGRyY2tKak0wVm5ORk52VDJSblptTXdSVTVxU2sxaFZrWlJVVUpmWDBOUlZsaE5OVmd5VXpCbVRr
ZGxkbTgwWTNRd1F6WkdMV3hmZVdnMmIyOUxVVWhpUzFKYWRYWkRVbkp4VldkdlNYSnJjamxETkd3
NWIyMUZURnBhTkdKVGRHbERNSGRuV2tkVVJqSkJXVTlZTXpRMFFqSTVORTlJWldFMlRUQjZiV0Zu
VkhKMVRIUlhTMWxmZGpnemJURkhkSEJzWm5ORlQyaFJYMGhFV2xKUGFTMXpNM1JrYmpNMmREQlRW
WFZQZEZJelVqaHhUMm8zVGtGTlJWOUVVVzk1VEY5dWFtVlNTSGx5V1hwVE1HeHhiazh0VVdKUmNq
VjBXV05CVVZwclNIVjFWRk5vZDA5b1JUVmxkakpHTUZrNWNFaElkWFZ5TkRWcFdGSlVVbFpWVUhO
Sk1tUnNWa2hCWjBGMFZqTkJNRVJSYjBobGRrbERWaTFWYkRneWNXRXphV1ZXVVVsZmJERlNVMWRI
VkRJemRGVkdPWEJPTmpKaE9HVTNPV3hMTTJGUVJrNTBjbXhXVFZGVFpFaFNjamQzIgogICAgfSwK
ICAgICJ0eXBlIjogImt1YmVybmV0ZXMuaW8vc2VydmljZS1hY2NvdW50LXRva2VuIgogIH0sCiAg
Imlwc2VjUFNLIjogewogICAgIm1ldGFkYXRhIjogewogICAgICAibmFtZSI6ICJzdWJtYXJpbmVy
LWlwc2VjLXBzayIKICAgIH0sCiAgICAiZGF0YSI6IHsKICAgICAgInBzayI6ICJGS1Vtb0xVdXZD
cTJtaGo5c3BQQ3BseXdtRzBnbXBxUjdTSWJRSVE5dTNFN3lHMjBCYy9CUkJzRDVVblNaNVVNIgog
ICAgfQogIH0sCiAgInNlcnZpY2VEaXNjb3ZlcnkiOiB0cnVlLAogICJDb21wb25lbnRzIjogWwog
ICAgImNvbm5lY3Rpdml0eSIsCiAgICAic2VydmljZS1kaXNjb3ZlcnkiCiAgXQp9Cg==
EOF

# Extract the broker's API connection info from the broker-info.subm file
brokerURL=$(cat ~/.pando/broker-info.subm | base64 -d | jq -r '.brokerURL')
namespace=$(cat ~/.pando/broker-info.subm | base64 -d | jq -r '.clientToken.metadata.namespace')
auth_token=$(cat ~/.pando/broker-info.subm | base64 -d | jq -r '.clientToken.data.token' | base64 -d)
cat ~/.pando/broker-info.subm | base64 -d | jq -r '.clientToken.data."ca.crt"' | base64 -d > ~/.pando/ca.crt

# Retrieve the cluster list
clusters=$(curl -s -H "Authorization: Bearer $auth_token" --cacert ~/.pando/ca.crt $brokerURL/apis/submariner.io/v1/namespaces/$namespace/clusters)
# echo "clusters=$clusters"
IN_USE_CIDRS=$(echo "$clusters" | jq -r '.items[].spec.cluster_cidr[]?, .items[].spec.service_cidr[]?')
# echo "IN_USE_CIDRS=$IN_USE_CIDRS"

if [ "$GENERATE_CLUSTER_CIDR" = "true" ]; then
    K3S_CLUSTER_CIDR=$(get_next_cidr "$IN_USE_CIDRS" "$K3S_CLUSTER_CIDR")
fi
if check_cidr "$K3S_CLUSTER_CIDR" "$clusters"; then
    echo "The specified cluster CIDR is already in use. Please select another or remove the --cluster-cidr argument to have a range selected automatically."
    exit 1
fi

if [ "$GENERATE_SERVICE_CIDR" = "true" ]; then
    IN_USE_CIDRS="$IN_USE_CIDRS
$K3S_CLUSTER_CIDR"
    K3S_SERVICE_CIDR=$(get_next_cidr "$IN_USE_CIDRS" "$K3S_SERVICE_CIDR")
fi
if check_cidr "$K3S_SERVICE_CIDR" "$clusters"; then
    echo "The specified service CIDR is already in use. Please select another or remove the --service-cidr argument to have a range selected automatically."
    exit 1
fi

echo "========== Configuration =========="
echo "CLUSTERID=$CLUSTERID"
echo "K3S_OPTIONS=$K3S_OPTIONS"
echo "GATEWAY=$GATEWAY"
echo "K3S_CLUSTER_CIDR=$K3S_CLUSTER_CIDR"
echo "K3S_SERVICE_CIDR=$K3S_SERVICE_CIDR"
echo -e "===================================\n"

if confirm "Proceed?"; then
    echo "Proceeding with installation..."
else
    echo "Cleaning up..."
    rm -rf ~/.pando
    exit 1
fi

# Install k3s
if [ `kubectl get nodes | grep ' Ready '| wc -l` -eq 0 ]; then
    echo "Installing k3s..."
    curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="$K3S_OPTIONS --cluster-cidr=$K3S_CLUSTER_CIDR --service-cidr=$K3S_SERVICE_CIDR" sh -
    if [[ `grep "export KUBECONFIG=$KUBECONFIG" ~/.bashrc |wc -l` -eq 0 ]]; then
        echo "export KUBECONFIG=$KUBECONFIG" >> ~/.bashrc
    fi
fi

# Make sure kubeconfig is available for future commands
KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Checking k3s has started..."
result=`kubectl get nodes | grep ' Ready '| wc -l`
startTime=`date +%s`
while [[ $result -eq 0 && `expr \`date +%s\` - $startTime` -lt 300 ]]; do
    sleep 2
    echo "Waiting for k3s nodes to be ready..."
    result=`kubectl get nodes | grep ' Ready '| wc -l`
done
if [ $result -eq 0 ]; then
    echo "There was a problem installing k3s..."
    exit 1
else
    echo "k3s is running!"
fi

echo "Checking kube-system is ready..."
result=`kubectl -n kube-system get pods | grep ' Running '| wc -l`
startTime=`date +%s`
while [[ $result -lt 3 && `expr \`date +%s\` - $startTime` -lt 300 ]]; do
    sleep 2
    echo "Waiting for kube-system to be ready..."
    result=`kubectl -n kube-system get pods | grep ' Running '| wc -l`
done
if [ $result -lt 3 ]; then
    echo "There was a problem starting k3s. Not all kube-system pods are ready."
    exit 1
else
    echo "kube-system is ready!"
fi

# If gateway is enabled, add the node label
if [ "$GATEWAY" = "true" ]; then
    kubectl get nodes -o name | xargs -I{} kubectl label {} "submariner.io/gateway=true"
fi

# Install subctl
echo "Installing subctl..."
curl -Ls https://get.submariner.io | bash
export PATH=$PATH:~/.local/bin
echo export PATH=\$PATH:~/.local/bin >> ~/.profile

# Join this node to PandoNet
if [ `kubectl -n submariner-operator get pods | grep ' Running '| wc -l` -eq 0 ]; then
    echo "Joining Pando Network..."
    SUBCTL_OPTS="--clusterid $CLUSTERID --enable-clusterset-ip --cable-driver wireguard"
    if [ "$GATEWAY" = "false" ]; then
        SUBCTL_OPTS+=" --natt=true"
    else
        SUBCTL_OPTS+=" --natt=false --preferred-server"
    fi
    echo "subctl join --kubeconfig $KUBECONFIG ~/.pando/broker-info.subm $SUBCTL_OPTS"
    subctl join --kubeconfig $KUBECONFIG ~/.pando/broker-info.subm $SUBCTL_OPTS
fi

# Check that all submariners pods are running
labels='app=submariner-routeagent|app=submariner-lighthouse-agent|app=submariner-lighthouse-coredns'
if [ "$GATEWAY" = "true" ]; then
    labels+='|app=submariner-gateway'
fi
numPodsExpected=$(printf "%s" "$labels" | tr -cd '|' | wc -c)
numPodsExpected=$(( $numPodsExpected + 1 ))
result=`kubectl -n submariner-operator get pods --show-labels | grep -E $labels | grep ' Running '| wc -l`
startTime=`date +%s`
while [[ $result -lt $numPodsExpected && `expr \`date +%s\` - $startTime` -lt 300 ]]; do
    sleep 2
    echo "Waiting for submariner to be ready..."
    result=`kubectl -n submariner-operator get pods --show-labels | grep -E $labels | grep ' Running '| wc -l`
done
if [ $result -eq 0 ]; then
    echo "There was a problem installing submariner..."
    exit 1
else
    echo "submariner is running!"
fi

# Check that we have a connection to at least one of the primary gateway cluster.
if [ "$GATEWAY" = "false" ]; then
    gateways=$(curl -s -H "Authorization: Bearer $auth_token" --cacert ~/.pando/ca.crt $brokerURL/apis/submariner.io/v1/namespaces/$namespace/gateways)
    result=`subctl --kubeconfig $KUBECONFIG show connections | grep -E 'dfw|sjc|was' | grep ' connected ' | wc -l`
    startTime=`date +%s`
    while [[ $result -eq 0 && `expr \`date +%s\` - $startTime` -lt 300 ]]; do
        sleep 2
        echo "Waiting for connection to gateway..."
        result=`subctl --kubeconfig $KUBECONFIG show connections | grep -E 'dfw|sjc|was' | grep ' connected ' | wc -l`
    done
    if [ $result -eq 0 ]; then
        echo "There was a problem establishing a connection to the gateway..."
        exit 1
    else
        echo "Pando is up and running. Welcome to the network!"
    fi
fi

# If this is going to be a gateway/proxy node for the network then setup a Gateway API controller
if [ "$GATEWAY" = "true" ]; then
    # Install nginx-gateway-fabric
    echo "Installing nginx-gateway-fabric"
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
    kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.2.1" \
    | kubectl apply -f -
    helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric --create-namespace -n nginx-gateway --set nginx.service.type=NodePort
    echo "Checking nginx-gateway-fabric has started..."
    result=`kubectl -n nginx-gateway get pods | grep -v 'Running' | wc -l`
    startTime=`date +%s`
    while [[ $result -ne 1 && `expr \`date +%s\` - $startTime` -lt 300 ]]; do
        sleep 2
        echo "Waiting for nginx-gateway-fabric to start..."
        result=`kubectl -n nginx-gateway get pods | grep -v 'Running' | wc -l`
    done
    if [ $result -ne 1 ]; then
        echo "There was a problem installing nginx-gateway-fabric..."
        exit 1
    else
        echo "nginx-gateway-fabric is running!"
    fi

    # Configure a single shared Gateway
    cat << EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: nginx-gateway
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    port: 443
    allowedRoutes:
      namespaces:
        from: All
EOF
    result=`kubectl -n nginx-gateway get svc -l 'gateway.networking.k8s.io/gateway-name=shared-gateway' | grep -E '80:[0-9]{1,5}/TCP(443:[0-9]{1,5}/TCP)?' | wc -l`
    startTime=`date +%s`
    while [[ $result -ne 1 && `expr \`date +%s\` - $startTime` -lt 300 ]]; do
        sleep 2
        echo "Waiting for shared-gateway to be ready..."
        result=`kubectl -n nginx-gateway get svc -l 'gateway.networking.k8s.io/gateway-name=shared-gateway' | grep -E '80:[0-9]{1,5}/TCP(443:[0-9]{1,5}/TCP)?' | wc -l`
    done
    if [ $result -ne 1 ]; then
        echo "There was a problem setting up the shared-gateway..."
        exit 1
    fi

    # Set up nginx reverse proxy
    echo "Installing nginx reverse proxy"
    if [[ -e /etc/redhat-release ]]; then
        if [ ! `dnf list installed | grep nginx` ]; then
            echo "Installing nginx for reverse proxy..."
            sudo dnf install nginx libnginx-mod-stream -y
            if [ $? -ne 0 ]; then
            echo "There was a problem installing nginx reverse proxy."
            exit 1
            fi
        fi
    else
        if [[ ! `apt list --installed | grep nginx` ]]; then
            echo "Installing nginx for reverse proxy..."
            sudo apt-get install nginx libnginx-mod-stream -y
            if [ $? -ne 0 ]; then
            echo "There was a problem installing nginx reverse proxy."
            exit 1
            fi
        fi
    fi

    # Extract the HTTP and HTTPS ports bound to the shared gateway
    HTTP_PORT=`kubectl -n nginx-gateway get svc -l 'gateway.networking.k8s.io/gateway-name=shared-gateway' -o jsonpath='{.items[].spec.ports[?(@.port==80)].nodePort}'`
    HTTPS_PORT=`kubectl -n nginx-gateway get svc -l 'gateway.networking.k8s.io/gateway-name=shared-gateway' -o jsonpath='{.items[].spec.ports[?(@.port==443)].nodePort}'`

    # Check if we've already written to this file before
    if grep -qzE 'listen 80;[[:space:]]+proxy_pass 127\.0\.0\.1:[0-9]{1,5};' /etc/nginx/nginx.conf; then
        echo "Updating nginx configuration..."
        sed -nEz 's#stream \{([^\}]|\n)*\}#stream {\n    server {\n        listen 80;\n        proxy_pass 127.0.0.1:'"$HTTP_PORT"';\n    }\n    server {\n        listen 443;\n        proxy_pass 127.0.0.1:'"$HTTPS_PORT"';\n    }\n}#' /etc/nginx/nginx.conf
    else
        echo "Backing up nginx.conf..."
        sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

        echo "Writing nginx configuration..."
        cat << EOF >> /etc/nginx/nginx.conf

stream {
    server {
        listen 80;
        proxy_pass 127.0.0.1:$HTTP_PORT;
    }
    server {
        listen 443;
        proxy_pass 127.0.0.1:$HTTPS_PORT;
    }
}
EOF
    fi

    if [[ -f /etc/nginx/sites-enabled/default ]]; then
        sudo rm /etc/nginx/sites-enabled/default
    fi
    
    sudo systemctl restart nginx
    if [ $? -ne 0 ]; then
        echo "There was a problem restarting nginx reverse proxy."
        exit 1
    fi
    sleep 10
    startTime=`date +%s`
    result=$(curl -s -o /dev/null -w "%{http_code}" http://localhost)
    while [[ $result -ge 500 && $result -lt 600 && `expr \`date +%s\` - $startTime` -lt 300 ]]; do
        sleep 2
        echo "Waiting for nginx to start..."
        result=$(curl -s -o /dev/null -w "%{http_code}" http://localhost)
    done
    if [[ $result -ge 500 && $result -lt 600 ]]; then
        echo "There was a problem configuring nginx reverse proxy."
        exit 1
    fi
    echo "Reverse proxy is setup."

    # Install cert-manager
    echo "Installing cert-manager"
    
    helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --namespace cert-manager --create-namespace \
        --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
        --set config.kind="ControllerConfiguration" \
        --set config.enableGatewayAPI=true \
        --set crds.enabled=true
    echo "Checking cert-manager has started..."
    result=`kubectl -n cert-manager get pods | grep -v 'Running' | wc -l`
    startTime=`date +%s`
    while [[ $result -ne 1 && `expr \`date +%s\` - $startTime` -lt 300 ]]; do
        sleep 2
        echo "Waiting for cert-manager to start..."
        result=`kubectl -n cert-manager get pods | grep -v 'Running' | wc -l`
    done
    if [ $result -ne 1 ]; then
        echo "There was a problem installing cert-manager..."
        exit 1
    else
        echo "cert-manager is running!"
    fi

    cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: pandocloud@outlook.com
    privateKeySecretRef:
      name: letsencrypt-issuer-key
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
          - name: shared-gateway
            namespace: nginx-gateway
            kind: Gateway
EOF
fi # if $gateway=true

echo "Pando installed successfully!"