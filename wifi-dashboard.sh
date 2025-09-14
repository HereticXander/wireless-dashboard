#!/bin/bash

# =========================================
# Ultimate Interactive Wi-Fi Dashboard
# =========================================
# Features:
# 1. Detects wireless interfaces automatically.
# 2. Scans all nearby Wi-Fi APs (all standards: a/b/g/n/ac/ax).
# 3. Estimates throughput based on standard, MCS, NSS, channel width.
# 4. Displays RSSI bars for signal strength.
# 5. Displays channel congestion bars.
# 6. Top 3 recommended APs (taking DFS into account).
# 7. Full table of all APs with color-coded throughput.
# 8. Interactive sorting:
#    - 's': sort by signal strength (RSSI)
#    - 't': sort by throughput (default)
#    - 'c': sort by channel load
#    - 'q': quit
# 9. Live refresh every 10 seconds.
# =========================================

# -----------------------------
# Function: estimate_throughput
# Returns estimated throughput in Mbps based on Wi-Fi standard.
# Parameters:
# 1. standard: Wi-Fi standard (n, ac, ax)
# 2. mcs: modulation coding scheme index
# 3. nss: number of spatial streams
# 4. width: channel width in MHz
# 5. freq: frequency in MHz (used for legacy estimation)
# -----------------------------
estimate_throughput() {
    local standard="$1"
    local mcs="$2"
    local nss="$3"
    local width="$4"
    local freq="$5"

    if [[ "$standard" == "ax" ]]; then
        # Wi-Fi 6 theoretical formula approximation
        local base=$((78*(mcs+1)))
        echo $((base * nss * width / 20))
    elif [[ "$standard" == "ac" ]]; then
        # Wi-Fi 5 (AC) approximation
        local base=$((86*(mcs+1)))
        echo $((base * nss * width / 20))
    elif [[ "$standard" == "n" ]]; then
        # Wi-Fi 4 (N) approximation
        local base=$((72*(mcs+1)))
        echo $((base * nss * width / 20))
    else
        # Legacy rates for a/b/g
        if [[ "$freq" -ge 5000 ]]; then
            echo 54
        else
            echo 54
        fi
    fi
}

# -----------------------------
# Detect first wireless interface
# -----------------------------
iface=$(iw dev | awk '/Interface/ {print $2; exit}')
if [ -z "$iface" ]; then
    echo "No wireless interfaces detected. Exiting."
    exit 1
fi

# -----------------------------
# Initialize interactive sort mode
# -----------------------------
sort_mode="throughput" # default sorting

# -----------------------------
# Function: check for key presses
# Allows interactive sorting without blocking
# -----------------------------
get_sort_key() {
    read -t 0.1 -n 1 key  # non-blocking read, 0.1 sec timeout
    case "$key" in
        s) sort_mode="rssi" ;;
        t) sort_mode="throughput" ;;
        c) sort_mode="chanload" ;;
        q) exit 0 ;;
    esac
}

# -----------------------------
# Main live-refresh loop
# -----------------------------
while true; do
    clear
    recommended_done=0

    # -----------------------------
    # Display dashboard legend
    # -----------------------------
    echo -e "\033[1;36mUltimate Wi-Fi Dashboard (Interface: $iface)\033[0m"
    echo -e "Colors = Throughput: \033[1;32mHigh\033[0m \033[32mMedium\033[0m \033[33mModerate\033[0m \033[31mLow\033[0m"
    echo -e "RSSI bars = Signal Strength (-100 to -30 dBm) | █ = ~5 dBm"
    echo -e "Channel Load bars = Congestion per channel | ▮ = relative load (Green=Low, Yellow=Med, Red=High)"
    echo -e "Sort: [s]=Signal, [t]=Throughput, [c]=Channel Load, [q]=Quit | Current sort: $sort_mode\n"

    # Check if user pressed a key for sorting
    get_sort_key

    # -----------------------------
    # Scan nearby APs
    # -----------------------------
    # Each line: SSID	BSSID	Freq/Width	Standard	DFS	Security	RSSI	MCS	NSS
    mapfile -t aps < <(sudo iw dev "$iface" scan 2>/dev/null | awk '
    BEGIN { FS=":"; OFS="\t" }
    /^BSS/ {bssid=$2; ssid=""; freq=""; width=""; standard=""; dfs=""; sec=""; rssi=""; mcs=0; nss=0}
    /SSID/ {ssid=$2}
    /freq/ {freq=$2}
    /channel width/ {width=$3}
    /signal/ {rssi=$2}
    /HT Capabilities/ {standard="n"}
    /VHT Capabilities/ {standard="ac"}
    /HE Capabilities/ {standard="ax"}
    /RSN/ {sec="WPA2"}
    /WPA3/ {sec="WPA3"}
    /WPA/ {sec="WPA"}
    /DFS/ {dfs="DFS"}
    {
        if(ssid!="" && freq!="" && standard!=""){
            print ssid,bssid,freq,width,standard,dfs,sec,rssi,mcs,nss
            ssid=""; freq=""; standard=""
        }
    }')

    # -----------------------------
    # Count APs per channel (channel congestion)
    # -----------------------------
    declare -A channel_counts
    aps_data=()
    for line in "${aps[@]}"; do
        IFS=$'\t' read -r ssid bssid freq width standard dfs sec rssi mcs nss <<< "$line"
        ((channel_counts[$freq]++))
    done

    # -----------------------------
    # Compute estimated throughput and real throughput per AP
    # -----------------------------
    for line in "${aps[@]}"; do
        IFS=$'\t' read -r ssid bssid freq width standard dfs sec rssi mcs nss <<< "$line"
        chan_load=${channel_counts[$freq]}
        est=$(estimate_throughput "$standard" "$mcs" "$nss" "$width" "$freq")
        # Adjust for channel congestion
        real_est=$((est / chan_load))
        aps_data+=("$ssid	$bssid	$freq/$width	$standard	$dfs	$sec	$rssi	$est	$chan_load	$real_est")
    done

    # -----------------------------
    # Sort APs based on user selection
    # -----------------------------
    case "$sort_mode" in
        rssi) sorted_aps=($(printf '%s\n' "${aps_data[@]}" | sort -nr -k7)) ;;
        throughput) sorted_aps=($(printf '%s\n' "${aps_data[@]}" | sort -nr -k10)) ;;
        chanload) sorted_aps=($(printf '%s\n' "${aps_data[@]}" | sort -n -k9)) ;;
        *) sorted_aps=("${aps_data[@]}") ;;
    esac

    # -----------------------------
    # Display Top 3 Recommended APs
    # -----------------------------
    top_aps=$(printf '%s\n' "${sorted_aps[@]}" | awk 'NR<=3 {print $0}')
    echo -e "========== TOP 3 RECOMMENDED APS =========="
    printf "%-25s %-17s %-12s %-5s %-5s %-9s %-22s %-20s %-9s %-8s\n" \
        "SSID" "BSSID" "Freq/Width" "Std" "DFS" "Sec" "RSSI" "Channel Load" "Est(Mbps)" "RealEst"
    echo "$top_aps" | while IFS=$'\t' read -r ssid bssid freqwidth standard dfs sec rssi est chan_load real_est; do
        # RSSI bar
        bar_length=$(( (100 + rssi) * 20 / 70 ))
        ((bar_length<0)) && bar_length=0
        ((bar_length>20)) && bar_length=20
        rssi_bar=$(printf '█%.0s' $(seq 1 $bar_length))
        # Channel load bar
        max_chan_load=0
        for count in "${channel_counts[@]}"; do (( count > max_chan_load )) && max_chan_load=$count; done
        load_bar_length=$(( chan_load * 20 / max_chan_load ))
        ((load_bar_length>20)) && load_bar_length=20
        load_bar=$(printf '▮%.0s' $(seq 1 $load_bar_length))
        if (( chan_load <= max_chan_load / 3 )); then load_color="\033[1;32m"
        elif (( chan_load <= 2*max_chan_load/3 )); then load_color="\033[33m"
        else load_color="\033[31m"
        fi
        printf "%-25s %-17s %-12s %-5s %-5s %-9s %-22s %-20s %-9s %-8s\n" \
            "$ssid" "$bssid" "$freqwidth" "$standard" "$dfs" "$sec" "$rssi_bar" "$load_color$load_bar\033[0m" "$est" "$real_est"
    done
    echo -e "===========================================\n"

    # -----------------------------
    # Full AP table
    # -----------------------------
    echo -e "SSID                     BSSID             Freq/Chan Width  Std   DFS  Sec       RSSI                   Channel Load           Est.Mbps  ChanLoad  RealEst  Recommended"
    echo -e "--------------------------------------------------------------------------------------------------------------------------------------------"

    recommended_done=0
    for entry in "${sorted_aps[@]}"; do
        IFS=$'\t' read -r ssid bssid freqwidth standard dfs sec rssi est chan_load real_est <<< "$entry"
        # RSSI bar
        bar_length=$(( (100 + rssi) * 20 / 70 ))
        ((bar_length<0)) && bar_length=0
        ((bar_length>20)) && bar_length=20
        rssi_bar=$(printf '█%.0s' $(seq 1 $bar_length))
        # Channel load bar
        max_chan_load=0
        for count in "${channel_counts[@]}"; do (( count > max_chan_load )) && max_chan_load=$count; done
        load_bar_length=$(( chan_load * 20 / max_chan_load ))
        ((load_bar_length>20)) && load_bar_length=20
        load_bar=$(printf '▮%.0s' $(seq 1 $load_bar_length))
        if (( chan_load <= max_chan_load / 3 )); then load_color="\033[1;32m"
        elif (( chan_load <= 2*max_chan_load/3 )); then load_color="\033[33m"
        else load_color="\033[31m"
        fi
        # Throughput color
        if (( real_est >= 600 )); then color="\033[1;32m"
        elif (( real_est >= 300 )); then color="\033[32m"
        elif (( real_est >= 150 )); then color="\033[33m"
        else color="\033[31m"
        fi

        rec=""
        if [[ $recommended_done -eq 0 && $dfs != "DFS" ]]; then
            rec="<-- Recommended"
            recommended_done=1
        fi

        printf "%s%-25s %-17s %-12s %-5s %-5s %-22s %-20s %-9s %-8s %s\033[0m\n" \
            "$color" "$ssid" "$bssid" "$freqwidth" "$standard" "$dfs" "$rssi_bar" "$load_color$load_bar\033[0m" "$est" "$real_est" "$rec"
    done

    echo -e "\nPress [s]=Signal, [t]=Throughput, [c]=Channel Load, [q]=Quit | Current sort: $sort_mode"
    sleep 10
done
