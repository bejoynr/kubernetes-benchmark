#!/bin/bash
BENCHMARK_DATE=$(date -u "+%Y-%m-%d %H:%M:%S")
SERVER_NODE=""
CLIENT_NODE=""
SERVER_POD_NAME="iperf-server"
CLIENT_POD_NAME="iperf-client"
SERVER_SERVICE_NAME="iperf-svc"
DATADIR="/tmp"
EXECID="$$"
BENCHMARK_RUN_NAME="knb-$EXECID"
NAMESPACEOPT="iperf"
POD_WAIT_TIMEOUT="30"
BENCHMARK_DURATION="10"
SOCKET_BUFFER_SIZE="auto"
##CMD="iperf3 -u -b 0 -c $TARGET -O 1 $SOCKET_BUFFER_FLAG -f m -t $BENCHMARK_DURATION"
function usage {
    cat <<-EOF

Benchmark tool for Kubernetes.........
    Mandatory flags :
    -cn <nodename>
    --client-node <nodename>    : Define kubernetes node name that will host the client part
    -sn <nodename>
    --server-node <nodename>    : Define kubernetes node name that will host the server part
    -n <namespace>
    --namespace <namespace>     : Set the target kubernetes namespace
EOF
}

#==============================================================================
# Argument parsing
#==============================================================================

[ "$1" = "" ] && usage && exit

UNKNOWN_ARGLIST=""
while [ "$1" != "" ]
do
    arg=$1
    case $arg in
        
        #--- Benchmark mode - Mandatory flags ---------------------------------
        # Define kubernetes node name that will host the client part
        --server-node|-sn)
            shift
            [ "$1" = "" ] && fatal "$arg flag must be followed by a value"
            SERVER_NODE=$1
            info "Server node will be '$SERVER_NODE'"
            ;;
        # Define kubernetes node name that will host the server part
        --client-node|-cn)
            shift
            [ "$1" = "" ] && fatal "$arg flag must be followed by a value"
            CLIENT_NODE=$1
            info "Client node will be '$CLIENT_NODE'"
            ;;
        # Set the benchmark duration for each test in seconds
        --duration|-d)
            shift
            [ "$1" = "" ] && fatal "$arg flag must be followed by a value"
            BENCHMARK_DURATION="$1"
            info "Setting benchmark duration to ${1}s"
            ;;
        # Set the target kubernetes namespace
        --namespace|-n)
            shift
            [ "$1" = "" ] && fatal "$arg flag must be followed by a value"
            NAMESPACEOPT="--namespace $1"
            info "Setting target namespace to '$1'"
           ;;
        # Set the name of this benchmark run
        --name)
            shift
            [ "$1" = "" ] && fatal "$arg flag must be followed by a value"
            BENCHMARK_RUN_NAME="$1"
            info "Setting benchmark run nameto '$1'"
            ;;
        # Set the pod ready wait timeout in seconds
        --timeout|-t)
            shift
            [ "$1" = "" ] && fatal "$arg flag must be followed by a value"
            POD_WAIT_TIMEOUT="$1"
            info "Setting pod wait timeout to ${1}s"
            ;;
        # Display help message
        --help|-h)
        usage && exit
            ;;
        # Unknown flag
        *) UNKNOWN_ARGLIST="$UNKNOWN_ARGLIST $arg" ;;
    esac
    shift
done

[ "$UNKNOWN_ARGLIST" != "" ] && fatal "Unknown arguments : $UNKNOWN_ARGLIST"
$DEBUG && debug "Argument parsing done"



#==============================================================================
# Data Detection
#==============================================================================

#--- CPU Detection ----------------------------------------

info "Detecting CPU"
DISCOVERED_CPU=$(kubectl exec -i  $NAMESPACEOPT $SERVER_POD_NAME -- grep "model name" /proc/cpuinfo | tail -n 1 | awk -F: '{print $2}')
$DEBUG && debug "Cpu is $DISCOVERED_CPU"
echo $DISCOVERED_CPU > $DATADIR/cpu

#--- Kernel Detection -------------------------------------

info "Detecting Kernel"
DISCOVERED_KERNEL=$(kubectl exec -i  $NAMESPACEOPT $SERVER_POD_NAME -- uname -r)
$DEBUG && debug "Kernel is $DISCOVERED_KERNEL"
echo $DISCOVERED_KERNEL > $DATADIR/kernel


#--- K8S Version Detection --------------------------------

info "Detecting Kubernetes version"
DISCOVERED_K8S_VERSION=$(kubectl version --short | awk '$1=="Server" {print $3}' )
$DEBUG && debug "Discovered k8s version is $DISCOVERED_K8S_VERSION"
echo $DISCOVERED_K8S_VERSION > $DATADIR/k8s-version

#--- MTU Detection ----------------------------------------

info "Detecting CNI MTU"
CNI_MTU=$(kubectl exec -i  $NAMESPACEOPT $SERVER_POD_NAME -- ip link \
    | grep "UP,LOWER_UP" | grep -v LOOPBACK | grep -oE "mtu [0-9]*"| $BIN_AWK '{print $2}')
$DEBUG && debug "CNI MTU is $CNI_MTU"
echo $CNI_MTU > $DATADIR/mtu

function compute-text-result {
    echo "========================================================="
    echo " Benchmark Results"
    echo "========================================================="
    echo " Name            : $BENCHMARK_RUN_NAME"
    echo " Date            : $BENCHMARK_DATE UTC"
    echo " Server          : $SERVER_NODE"
    echo " Client          : $CLIENT_NODE"
    echo "========================================================="
    echo "  Discovered CPU         : $(cat $DATADIR/cpu)"
    echo "  Discovered Kernel      : $(cat $DATADIR/kernel)"
    echo "  Discovered k8s version : $(cat $DATADIR/k8s-version)"
    echo "  Discovered MTU         : $(cat $DATADIR/mtu)"
}

info "Deploying iperf server on node $SERVER_NODE"
cat <<EOF | kubectl apply $NAMESPACEOPT -f - >/dev/null|| fatal "Cannot create server pod"
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: $SERVER_POD_NAME
  name: $SERVER_POD_NAME
spec:
  containers:
  - name: iperf
    image: infrabuilder/netbench:server-iperf3
    args:
    - iperf3
    - -s
  nodeSelector:
    kubernetes.io/hostname: $SERVER_NODE
---
apiVersion: v1
kind: Service
metadata:
  name: $SERVER_SERVICE_NAME
spec:
  selector:
    app: $SERVER_POD_NAME
  ports:
    - protocol: TCP
      port: 5201
      targetPort: 5201
      name: tcp
    - protocol: UDP
      port: 5201
      targetPort: 5201
      name: udp
EOF
info "Starting pod $POD_NAME on node $CLIENT_NODE"
cat <<-EOF | kubectl apply $NAMESPACEOPT -f - >/dev/null|| fatal "Cannot create pod $POD_NAME"
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: $CLIENT_POD_NAME
  name: $CLIENT_POD_NAME
spec:
spec:
  containers:
  - args:
    - bash
    image: bejoyr/difi-benchmark:v2
    imagePullPolicy: Always
    name: debian1
    stdin: true
    stdinOnce: true
    tty: true
  nodeSelector:
    kubernetes.io/hostname: $CLIENT_NODE
  restartPolicy: Never
EOF
compute-text-result
