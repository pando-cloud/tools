#!/usr/bin/env bash
CLUSTERID=`hostname`
K3S_OPTIONS="--disable=traefik"
GATEWAY=false
UNINSTALL=false

uninstall() {
  echo "Removing k3s..."
  sudo /usr/local/bin/k3s-uninstall.sh
  echo "Removing subctl..."
  rm ~/.local/bin/subctl
  rm -rf ~/.pando
  echo "Uninstall complete!"
}

GETOPT=$(getopt -o g,o,u,h --long clusterid:,k3s-options:,gateway,uninstall,help -- "$@")
eval set -- "$GETOPT"
while true
do
    case "$1" in
        --clusterid) CLUSTERID="$2"; shift 2;;
        --k3s-options) K3S_OPTIONS+=" $2"; shift 2;;
        -g | --gateway) GATEWAY=true; shift;;
        --uninstall) UNINSTALL=true; shift;;
        -h | --help)
          echo "This script installs PandoNet and configures the machine as a worker node on the network."

          echo "Usage:"
          echo -e "\t--clusterid <name>\t\tThe unique name of the machine to register to PandoNet. Defaults to `hostname`"
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

echo "Configuration:"
echo "CLUSTERID=$CLUSTERID"
echo "K3S_OPTIONS=$K3S_OPTIONS"
echo "GATEWAY=$GATEWAY"

# Install k3s
if [ `kubectl get nodes| grep ' Ready '| wc -l` -eq 0 ]; then
    echo "Installing k3s..."
    curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="$K3S_OPTIONS" sh -
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    if [[ `grep "export KUBECONFIG=$KUBECONFIG" ~/.bashrc |wc -l` -eq 0 ]]; then
        echo "export KUBECONFIG=$KUBECONFIG" >> ~/.bashrc
    fi
fi

echo "Checking k3s has started..."
result=`kubectl get nodes | grep ' Ready '| wc -l`
startTime=`date +%s`
while [[ $result -eq 0 && `expr \`date +%s\` - $startTime` -lt 1800 ]]; do
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

# If gateway is enabled, add the node label
if [ "$GATEWAY" = "true" ]; then
    kubectl get nodes -o name | xargs -I{} kubectl label {} "submariner.io/gateway=true"
fi

# Install subctl
echo "Installing subctl..."
curl -Ls https://get.submariner.io | bash
export PATH=$PATH:~/.local/bin
echo export PATH=\$PATH:~/.local/bin >> ~/.profile

# Create the broker-info.subm file needed to join PandoNet
mkdir -p ~/.pando
cat <<'EOF' > ~/.pando/broker-info.subm
ewogICJicm9rZXJVUkwiOiAiaHR0cHM6Ly81NC4xODMuMjA0LjE2Njo2NDQzIiwKICAiY2xpZW50
VG9rZW4iOiB7CiAgICAibWV0YWRhdGEiOiB7CiAgICAgICJuYW1lIjogInN1Ym1hcmluZXItazhz
LWJyb2tlci1hZG1pbi10b2tlbi04cWdubiIsCiAgICAgICJnZW5lcmF0ZU5hbWUiOiAic3VibWFy
aW5lci1rOHMtYnJva2VyLWFkbWluLXRva2VuLSIsCiAgICAgICJuYW1lc3BhY2UiOiAic3VibWFy
aW5lci1rOHMtYnJva2VyIiwKICAgICAgInVpZCI6ICIxNjBiYTU3My03ZmIwLTQ3NzgtODQ1Ni05
N2QwMTVjNWRmZTkiLAogICAgICAicmVzb3VyY2VWZXJzaW9uIjogIjI1MjUiLAogICAgICAiY3Jl
YXRpb25UaW1lc3RhbXAiOiAiMjAyNi0wMi0xMVQxOTo0NDozN1oiLAogICAgICAiYW5ub3RhdGlv
bnMiOiB7CiAgICAgICAgImt1YmVybmV0ZXMuaW8vY3JlYXRlZC1ieSI6ICJzdWJjdGwiLAogICAg
ICAgICJrdWJlcm5ldGVzLmlvL3NlcnZpY2UtYWNjb3VudC5uYW1lIjogInN1Ym1hcmluZXItazhz
LWJyb2tlci1hZG1pbiIsCiAgICAgICAgImt1YmVybmV0ZXMuaW8vc2VydmljZS1hY2NvdW50LnVp
ZCI6ICI3Y2RkNDVjZi0xNDc1LTRkOWQtYmI2Yy0xYTNmZWRhYzExMWEiCiAgICAgIH0sCiAgICAg
ICJtYW5hZ2VkRmllbGRzIjogWwogICAgICAgIHsKICAgICAgICAgICJtYW5hZ2VyIjogImszcyIs
CiAgICAgICAgICAib3BlcmF0aW9uIjogIlVwZGF0ZSIsCiAgICAgICAgICAiYXBpVmVyc2lvbiI6
ICJ2MSIsCiAgICAgICAgICAidGltZSI6ICIyMDI2LTAyLTExVDE5OjQ0OjM3WiIsCiAgICAgICAg
ICAiZmllbGRzVHlwZSI6ICJGaWVsZHNWMSIsCiAgICAgICAgICAiZmllbGRzVjEiOiB7CiAgICAg
ICAgICAgICJmOmRhdGEiOiB7CiAgICAgICAgICAgICAgIi4iOiB7fSwKICAgICAgICAgICAgICAi
ZjpjYS5jcnQiOiB7fSwKICAgICAgICAgICAgICAiZjpuYW1lc3BhY2UiOiB7fSwKICAgICAgICAg
ICAgICAiZjp0b2tlbiI6IHt9CiAgICAgICAgICAgIH0sCiAgICAgICAgICAgICJmOm1ldGFkYXRh
IjogewogICAgICAgICAgICAgICJmOmFubm90YXRpb25zIjogewogICAgICAgICAgICAgICAgImY6
a3ViZXJuZXRlcy5pby9zZXJ2aWNlLWFjY291bnQudWlkIjoge30KICAgICAgICAgICAgICB9CiAg
ICAgICAgICAgIH0KICAgICAgICAgIH0KICAgICAgICB9LAogICAgICAgIHsKICAgICAgICAgICJt
YW5hZ2VyIjogInN1YmN0bCIsCiAgICAgICAgICAib3BlcmF0aW9uIjogIlVwZGF0ZSIsCiAgICAg
ICAgICAiYXBpVmVyc2lvbiI6ICJ2MSIsCiAgICAgICAgICAidGltZSI6ICIyMDI2LTAyLTExVDE5
OjQ0OjM3WiIsCiAgICAgICAgICAiZmllbGRzVHlwZSI6ICJGaWVsZHNWMSIsCiAgICAgICAgICAi
ZmllbGRzVjEiOiB7CiAgICAgICAgICAgICJmOm1ldGFkYXRhIjogewogICAgICAgICAgICAgICJm
OmFubm90YXRpb25zIjogewogICAgICAgICAgICAgICAgIi4iOiB7fSwKICAgICAgICAgICAgICAg
ICJmOmt1YmVybmV0ZXMuaW8vY3JlYXRlZC1ieSI6IHt9LAogICAgICAgICAgICAgICAgImY6a3Vi
ZXJuZXRlcy5pby9zZXJ2aWNlLWFjY291bnQubmFtZSI6IHt9CiAgICAgICAgICAgICAgfSwKICAg
ICAgICAgICAgICAiZjpnZW5lcmF0ZU5hbWUiOiB7fQogICAgICAgICAgICB9LAogICAgICAgICAg
ICAiZjp0eXBlIjoge30KICAgICAgICAgIH0KICAgICAgICB9CiAgICAgIF0KICAgIH0sCiAgICAi
ZGF0YSI6IHsKICAgICAgImNhLmNydCI6ICJMUzB0TFMxQ1JVZEpUaUJEUlZKVVNVWkpRMEZVUlMw
dExTMHRDazFKU1VKbFJFTkRRVkl5WjBGM1NVSkJaMGxDUVVSQlMwSm5aM0ZvYTJwUFVGRlJSRUZx
UVdwTlUwVjNTSGRaUkZaUlVVUkVRbWh5VFROTmRHTXlWbmtLWkcxV2VVeFhUbWhSUkVVelRucEJO
RTE2V1RGUFZFMTNTR2hqVGsxcVdYZE5ha1Y0VFZScmQwMTZSWHBYYUdOT1RYcFpkMDFxUVRWTlZH
dDNUWHBGZWdwWGFrRnFUVk5GZDBoM1dVUldVVkZFUkVKb2NrMHpUWFJqTWxaNVpHMVdlVXhYVG1o
UlJFVXpUbnBCTkUxNldURlBWRTEzVjFSQlZFSm5ZM0ZvYTJwUENsQlJTVUpDWjJkeGFHdHFUMUJS
VFVKQ2QwNURRVUZSUTI1dGVuTTNWSHBCVGtSaGN6ZHhTblpPU3pNeWVrYzBRaTh5YTNsYVJuRnZj
azFCWlRJd1lrSUtLMWxzYnpJclUxZE5jakl2TUdwTWRERktWMloxZVRCbldGWlFkSFJRWWpoUlZG
cGFkblZ0TWt0b2JtbHZNRWwzVVVSQlQwSm5UbFpJVVRoQ1FXWTRSUXBDUVUxRFFYRlJkMFIzV1VS
V1VqQlVRVkZJTDBKQlZYZEJkMFZDTDNwQlpFSm5UbFpJVVRSRlJtZFJWV1JvYlZSR1ZIZE5TbVZh
U2s5REswdE9WbTlPQ25WeFJHbFRTREIzUTJkWlNVdHZXa2w2YWpCRlFYZEpSRk5SUVhkU1owbG9R
VXhRTTBSRGVUVkdZazh5WW5oWGRpOXpiV3RMT0RCaFFXMXhXVk56V0d3S1NEVTBaVWR6TVdoR1kz
WkJRV2xGUVRSd1VGWkdaRGxTZEdrMk5GbGFjR2hwVDJsQmJIQktRVWN3TUdORmEwbHpjV1pOWkda
U01taFhiMUU5Q2kwdExTMHRSVTVFSUVORlVsUkpSa2xEUVZSRkxTMHRMUzBLIiwKICAgICAgIm5h
bWVzcGFjZSI6ICJjM1ZpYldGeWFXNWxjaTFyT0hNdFluSnZhMlZ5IiwKICAgICAgInRva2VuIjog
IlpYbEthR0pIWTJsUGFVcFRWWHBKTVU1cFNYTkpiWFJ3V2tOSk5rbHVRa2RUUkdSdVRrWlJORkZy
TVRKU01EVkxWakk1VUdOVmNETlhhMmd6VldreFNGRXlOVzlWYm1SdFZrUnNXbEpyY0cxaFJWWldW
VWM0YVdaUkxtVjVTbkJqTTAxcFQybEtjbVJYU214amJUVnNaRWRXZWt3elRteGpibHB3V1RKV2FG
a3lUblprVnpVd1NXbDNhV0V6Vm1sYVdFcDFXbGhTYkdONU5YQmllVGw2V2xoS01tRlhUbXhaVjA1
cVlqTldkV1JET1hWWlZ6RnNZek5DYUZreVZXbFBhVXA2WkZkS2RGbFlTbkJpYlZaNVRGZHpOR041
TVdsamJUbHlXbGhKYVV4RFNuSmtWMHBzWTIwMWJHUkhWbnBNYld4MlRETk9iR051V25CWk1sWm9X
VEpPZG1SWE5UQk1NMDVzV1ROS2JHUkROWFZaVnpGc1NXcHZhV016Vm1saVYwWjVZVmMxYkdOcE1Y
SlBTRTEwV1c1S2RtRXlWbmxNVjBacllsZHNkVXhZVW5aaE1sWjFURlJvZUZveU5YVkphWGRwWVRO
V2FWcFlTblZhV0ZKc1kzazFjR0o1T1hwYVdFb3lZVmRPYkZsWFRtcGlNMVoxWkVNNWVscFlTakpo
VjA1c1RGZEdhbGt5T1RGaWJsRjFZbTFHZEZwVFNUWkpiazR4V1cweGFHTnRiSFZhV0VsMFlYcG9l
a3hYU25saU1uUnNZMmt4YUZwSE1YQmlhVWx6U1cxME1WbHRWbmxpYlZZd1dsaE5kV0ZYT0haak1s
WjVaRzFzYWxwWFJtcFpNamt4WW01UmRtTXlWbmxrYld4cVdsTXhhRmt5VG5aa1Z6VXdURzVXY0Zw
RFNUWkphbVJxV2tkUk1FNVhUbTFNVkVVd1RucFZkRTVIVVRWYVF6RnBXV3BhYWt4VVJtaE5NbHBz
V2tkR2FrMVVSWGhaVTBselNXNU9NVmxwU1RaSmJrNDFZek5TYkdKVWNIcGFXRW95WVZkT2JGbFhU
bXBpTTFaMVpFUndlbVJYU25SWldFcHdZbTFXZVV4WGN6UmplVEZwWTIwNWNscFlTVFpqTTFacFls
ZEdlV0ZYTld4amFURnlUMGhOZEZsdVNuWmhNbFo1VEZkR2EySlhiSFZKYmpBdVN6QjRabVJKVUdO
YU9VaFVYMHR0Y1VwelJVSnZjaTFuVW1wbFQzSTRRa3AxUjJOTU9USkpXRXQ0ZUZrNVFtOXljSEZa
Vm1reGJ6QkNWRkJIY1RoV05tdGxWbGh5YlcxeE9UZDZiekJEZG1SekxXMTBka1JoY25GUk9YZHVP
VFl6YUZsaWJEbFJSVTFmYVhKdFRrcGZWRlUxU1RGeVJ6aFRNRU42TUhOWVJGOXJUSGhMTjJKVFVI
ZFlWRzlXWlhCWlUzVldVa2hvYW1keFV6VTJjR3h0TFZSelNWWk1iMkZvTFVsNVZURmFTMU5uUWxB
eGFVSkJOSFJqUTBOM1JqaHZXakpuYnkxdVgyMWthbGhIVURoNFJrcHliREZrUjI1d1ZVZEZUR3BY
Tld4SWRuRjVSa1puWWpoRVNEaElUMFZMZGxCUFRqRkZVamhmUnpoelZrNW1hRVZ0ZGtOTFVHNUJV
SGRDZVdsd1oxVlNUREJ1ZFdSUGJtczVRVGRqUlhVekxXdG9jbFZvWkZGRVltVkZkWHBRV0VodlFW
Sm9MVVJyUVc5bU4xazFlbkJFWmxFNUxVMUdObXgyWVhwcFJuRjNVRUpQZERSMyIKICAgIH0sCiAg
ICAidHlwZSI6ICJrdWJlcm5ldGVzLmlvL3NlcnZpY2UtYWNjb3VudC10b2tlbiIKICB9LAogICJp
cHNlY1BTSyI6IHsKICAgICJtZXRhZGF0YSI6IHsKICAgICAgIm5hbWUiOiAic3VibWFyaW5lci1p
cHNlYy1wc2siCiAgICB9LAogICAgImRhdGEiOiB7CiAgICAgICJwc2siOiAiaUhOcW1hQXZpYjh0
NFJtc0hNNWVXVEJPZnZWMXhvR2xpbS90REs2QnBXanhYZEhaWVFMRDdrSCs1TVFHWUVUMSIKICAg
IH0KICB9LAogICJzZXJ2aWNlRGlzY292ZXJ5IjogdHJ1ZSwKICAiQ29tcG9uZW50cyI6IFsKICAg
ICJjb25uZWN0aXZpdHkiLAogICAgInNlcnZpY2UtZGlzY292ZXJ5IgogIF0KfQo=
EOF

# Join this node to PandoNet
if [ `kubectl -n submariner-operator get pods | grep ' Running '| wc -l` -eq 0 ]; then
    SUBCTL_OPTS="--clusterid $CLUSTERID"
    if [ "$GATEWAY" = "false" ]; then
        SUBCTL_OPTS+=" --natt=true"
    fi
    subctl join --kubeconfig /etc/rancher/k3s/k3s.yaml ~/.pando/broker-info.subm $SUBCTL_OPTS
fi

# Check that all submariners pods are running
result=`kubectl -n submariner-operator get pods | grep ' Running '| wc -l`
startTime=`date +%s`
while [[ $result -lt 8 && `expr \`date +%s\` - $startTime` -lt 1800 ]]; do
    sleep 2
    echo "Waiting for submariner to be ready..."
    result=`kubectl -n submariner-operator get pods | grep ' Running '| wc -l`
done
if [ $result -eq 0 ]; then
    echo "There was a problem installing submariner..."
    exit 1
else
    echo "submariner is running!"
fi

# Check that we have a connection to at least one of the primary proxy clusters
result=`subctl show connections | grep -E '(dfw|sjc|was)-proxy' | grep ' connected ' | wc -l`
startTime=`date +%s`
while [[ $result -gt 0 && `expr \`date +%s\` - $startTime` -lt 1800 ]]; do
    sleep 2
    echo "Waiting for connection to gateway..."
    result=`subctl show connections | grep -E '(dfw|sjc|was)-proxy' | grep ' connected ' | wc -l`
done
if [ $result -eq 0 ]; then
    echo "There was a problem establishing a connection to the gateway..."
    exit 1
else
    echo "Pando is up and running. Welcome to the network!"
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
    while [[ $running && $result -ne 1 && `expr \`date +%s\` - $startTime` -lt 1800 ]]; do
    sleep 2
    echo "Waiting for nginx-gateway-fabric to start..."
    result=`kubectl -n nginx get pods | grep -v 'Running' | wc -l`
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
    result=`kubectl -n nginx-gateway get svc | grep -E '80:[0-9]{1,5}/TCP(443:[0-9]{1,5}/TCP)?' | wc -l`
    startTime=`date +%s`
    while [[ $running && $result -ne 1 && `expr \`date +%s\` - $startTime` -lt 1800 ]]; do
    sleep 2
    echo "Waiting for shared-gateway to be ready..."
    result=`kubectl -n nginx-gateway get svc | grep -E '80:[0-9]{1,5}/TCP(443:[0-9]{1,5}/TCP)?' | wc -l`
    done
    if [ $result -ne 1 ]; then
    echo "There was a problem setting up the shared-gateway..."
    exit 1
    fi

    # Extract the HTTP and HTTPS ports bound to the shared gateway
    HTTP_PORT=`kubectl -n nginx-gateway get svc shared-gateway -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}'`
    HTTPS_PORT=`kubectl -n nginx-gateway get svc shared-gateway -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}'`

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
    if [ `cat /etc/nginx/nginx.conf | grep "proxy_pass 127.0.0.1:30080" | wc -l` -eq 0 ]; then
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
    if [[ -f /etc/nginx/sites-enabled/default ]]; then
        sudo rm /etc/nginx/sites-enabled/default
    fi
    sudo systemctl restart nginx
    if [ $? -ne 0 ]; then
        echo "There was a problem restarting nginx reverse proxy."
        exit 1
    fi
    sleep 10
    NGINX_READY=0
    startTime=`date +%s`
    while [[ $running && $result -ne 1 && `expr \`date +%s\` - $startTime` -lt 1800 ]]; do
        sleep 2
        echo "Waiting for nginx to start..."
        curl http://localhost
        if [ $? -eq 0 ]; then
        NGINX_READY=1
        fi
    done
    if [ $NGINX_READY -eq 0 ]; then
        echo "There was a problem configuring nginx reverse proxy."
        exit 1
    fi
    fi
    echo "Reverse proxy is setup."

    # Install cert-manager
    echo "Installing cert-manager"
    
    helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --namespace cert-manager --create-namespace \
        --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
        --set config.kind="ControllerConfiguration" \
        --set config.enableGatewayAPI=true \
        --set installCRDs=true
    echo "Checking cert-manager has started..."
    result=`kubectl -n cert-manager get pods | grep -v 'Running' | wc -l`
    startTime=`date +%s`
    while [[ $running && $result -ne 1 && `expr \`date +%s\` - $startTime` -lt 1800 ]]; do
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
kind: Issuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: pandocloud@outlook.com
    solvers:
    - http01:
    gatewayHTTPRoute:
      parentRefs:
      - name: shared-gateway
        namespace: nginx-gateway
        kind: Gateway
EOF
fi # if $gateway=true