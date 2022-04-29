read -e -p "Node Capacity: " -i 1400000000 CAPACITY
read -e -p "7 day earnings: " -i 100000 EARNING
read -e -p "7 day routed: " -i 0 ROUTED
EARNING=${EARNING:-100000}
CAPACITY=${CAPACITY:-750000000}
ROUTED=${ROUTED:-150000000}
zero_capacity=0
total_paid=0
DEBUG=':'

function print_ath_data()
{
current_block="`bos call getheight | grep current_block_height | cut -d : -f2`"; $DEBUG "Current Block $current_block";
declare -a ath_data_arr; mapfile -t ath_data_arr < athdata; $DEBUG ${ath_data_arr[@]};

ppm=$((EARNING*1000000/CAPACITY*ROUTED/zero_capacity));

[[ ${ath_data_arr[0]} -lt $total_paid ]] && { ath_data_arr[0]=$total_paid; ath_data_arr[1]=$current_block; }
[[ ${ath_data_arr[2]} -lt $ppm ]] && { ath_data_arr[2]=$ppm; ath_data_arr[3]=$current_block; }
[[ ${ath_data_arr[4]} -lt $zero_cnt ]] && { ath_data_arr[4]=$zero_cnt; ath_data_arr[5]=$current_block; }
[[ ${ath_data_arr[6]} -lt $zero_capacity ]] && { ath_data_arr[6]=$zero_capacity; ath_data_arr[7]=$current_block; }

#Record for next run
echo ${ath_data_arr[@]} | sed 's/ /\n/g' > athdata

#Printout
echo "------------";
echo "ATH Record for #GSpotSuperNode";
printf "%-10s %12d %8d\n" "Payout" ${ath_data_arr[0]} ${ath_data_arr[1]};
printf "%-10s %12d %8d\n" "Net ppm" ${ath_data_arr[2]} ${ath_data_arr[3]};
printf "%-10s %12d %8d\n" "Peers" ${ath_data_arr[4]} ${ath_data_arr[5]};
printf "%-10s %12d %8d\n" "Capacity" ${ath_data_arr[6]} ${ath_data_arr[7]};
echo "------------";
}

function get_zero_capacity()
{
 local own_arr=( `cat own_initiated` )

 local dualfunded_arr=( `cat dual_funded` )

 local excluded_arr=( `cat excluded_nodes` )

 lncli listchannels > channels

 cat channels | grep -e "remote_pubkey" -e "capacity" | awk -F: '{gsub(/^[ \t]+/, "", $2);print $2}' | sed -e 's/"//g' -e 's/,//g' -e 's/ //g' -e 's/\r//g' > channels_capacity

 local zerofee_peers=(`bos peers --no-color --complete \
  | grep -e "inbound_fee_rate:" -e "public_key:" | grep -v "partner_public_key:" | grep "(0)" -A1 \
  | grep "public_key:" | awk -F : '{gsub(/^[ \t]+/, "", $2);print $2}'`)

 echo "${zerofee_peers[@]}" | sed 's/ 0/\n0/g' > zerofee_peers

 zero_cnt=0
 for i in "${zerofee_peers[@]}"
 do
  echo "----------"
  echo "checking $i"; grep $i ~/utils/peers | tail -7
  days_cnt=`grep $i ~/utils/peers | tail -7 | grep "(0)" | grep -v -e "💀" -e "🚫" | wc -l`; echo "zero fees days $days_cnt/7";

  if [[ $days_cnt = 0 ]]
  then
   echo "### Not zero fee for $i ... skipping ..."; continue;
  elif [[ $days_cnt < 7 ]]
  then
   echo " ### only $days_cnt / 7 for $i ... adjusting ...";
  fi

  if [[ ${own_arr[*]} =~ $i ]]
  then
   echo "### Own Channel $i ... skipping ..."
   continue;
  elif [[ ${excluded_arr[*]} =~ $i ]]
  then
   echo "### Excluded Channel $i ... skipping ..."
   continue;
  else
   ((zero_cnt+=1))
  fi

  peer_capacity=0
  peer_capacity_arr=(`grep $i -A1 channels_capacity | grep -v $i | sed 's/ //g' | awk '{gsub(/^[ \t]+/, "", $1);print $1}'`);

  if [[ ${dualfunded_arr[*]} =~ $i ]]
  then
   echo "### Dual funded $i .. adjusting ..."
   divisor=2
  else
   divisor=1
  fi

  for j in "${peer_capacity_arr[@]}"
  do
   ((j/=divisor))
   ((peer_capacity+=$j));
   ((zero_capacity+=$j));
  done

  #Adjust Peer Capacity to Days_Count
  echo $i $((peer_capacity * days_cnt/7)) | tee -a zero_peer_capacity
  echo "----------"
 done

 # Set Routed <= 0 to disable routed adjustment.

 if [ $ROUTED -gt $zero_capacity ] || [ $ROUTED -le 0 ]
 then
  echo "### Adjusting Routed = $zero_capacity ..."
  ROUTED=$zero_capacity
 else
  echo "... Routed $ROUTED Zero_Capacity $zero_capacity ..."
 fi
}

cat /dev/null > zero_peer_capacity

echo "... collecting zero capacity peers"; get_zero_capacity;

echo "working with $EARNING for last 7 days earning with $CAPACITY node capacity, $zero_capacity ZERO CAPACITY over $ROUTED 7 day routed"
echo "----------"

mv bospayscript bospayscript.`date +%Y%m%d`

echo "date" > bospayscript

while read -r peer peer_capacity
do

 $DEBUG "$peer $peer_capacity $zero_capacity"
 fee_due=`echo " $EARNING * $peer_capacity / $CAPACITY * $ROUTED / $zero_capacity " | bc -q`; ((total_paid+=fee_due)); $DEBUG "will pay $fee_due to $i"
 msg1="#GSpotSuperNode Your weekly gift of $fee_due from g-spot was paid via bos gift as routing fees. Thank you for being my super node partner with 0/0 fees"
 msg2="#GSpotSuperNode Your weekly gift of $fee_due from g-spot. Thank you for being my super node partner with 0/0 fees"

 #Send as gift + 1 sat keysend  or else normal keysend.
 echo 'echo "----------"' >> bospayscript
 echo "echo paying $fee_due $peer" >> bospayscript
 $DEBUG "$fee_due $peer"
 echo "bos gift $peer $fee_due && { bos send $peer --amount 1 --message '$msg1' --max-fee 1 || echo '... Failed. Could be CLN. Ignore ...'; } || { bos send $peer --amount $fee_due --max-fee 1 --message '$msg2' --max-fee 1 || bos send $peer --amount $fee_due --max-fee 1; }" >> bospayscript
 echo 'echo' >> bospayscript
done < zero_peer_capacity

echo
echo "#GSpotSuperNode"
echo "=== Weekly Update ==="
echo "Shared a gift with $zero_cnt super node partners peers of $total_paid sats. That is $((EARNING*1000000/CAPACITY*ROUTED/zero_capacity)) ppm net fee to my peers on their deployed balance with my node"
echo "total GSpotSuperNode peer capacity $zero_capacity representing $((zero_capacity*100/CAPACITY))% of node"
print_ath_data;
echo "Join #GSpotSuperNode to take part"
echo

echo "Run . ./bospayscript to pay"