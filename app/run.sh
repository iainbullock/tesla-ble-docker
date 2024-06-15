#!/bin/ash
set +e

echo "tesla_ble_mqtt_docker by Iain Bullock 2024 https://github.com/iainbullock/tesla_ble_mqtt_docker"
echo "Inspiration by Raphael Murray https://github.com/raphmur"
echo "Instructions by Shankar Kumarasamy https://shankarkumarasamy.blog/2024/01/28/tesla-developer-api-guide-ble-key-pair-auth-and-vehicle-commands-part-3"

echo "Configuration Options are:"
echo TESLA_VIN=$TESLA_VIN
echo BLE_MAC=$BLE_MAC
echo MQTT_IP=$MQTT_IP
echo MQTT_PORT=$MQTT_PORT
echo MQTT_USER=$MQTT_USER
echo "MQTT_PWD=Not Shown"
echo SEND_CMD_RETRY_DELAY=$SEND_CMD_RETRY_DELAY

send_command() {
 for i in $(seq 5); do
  echo "Attempt $i/5"
  tesla-control -ble -key-name private.pem -key-file private.pem $1
  if [ $? -eq 0 ]; then
    echo "Ok"
    break
  fi
  sleep $SEND_CMD_RETRY_DELAY
 done 
}

listen_to_ble() {
 echo "Listening to BLE"
 bluetoothctl --timeout 2 scan on | grep $BLE_MAC
 if [ $? -eq 0 ]; then
   echo "$BLE_MAC presence detected"
   mosquitto_pub --nodelay -h $MQTT_IP -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PWD -t tesla_ble/binary_sensor/presence -m ON
 else
   echo "$BLE_MAC presence not detected"
   mosquitto_pub --nodelay -h $MQTT_IP -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PWD -t tesla_ble/binary_sensor/presence -m OFF
 fi
}

listen_to_mqtt() {
 echo "Listening to MQTT"
 mosquitto_sub --nodelay -E -c -i tesla_ble_mqtt -q 1 -h $MQTT_IP -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PWD -t tesla_ble/+ -t homeassistant/status -F "%t %p" | while read -r payload
  do
   topic=$(echo "$payload" | cut -d ' ' -f 1)
   msg=$(echo "$payload" | cut -d ' ' -f 2-)
   echo "Received MQTT message: $topic $msg"
   case $topic in
    tesla_ble/config)
     echo "Configuration $msg requested"
     case $msg in
      generate_keys)
       echo "Generating the private key"
       openssl ecparam -genkey -name prime256v1 -noout > private.pem
       cat private.pem
       echo "Generating the public key"
       openssl ec -in private.pem -pubout > public.pem
       cat public.pem
       echo "Keys generated, ready to deploy to vehicle. Remove any previously deployed keys from vehicle before deploying this one";;
      deploy_key) 
       echo "Deploying public key to vehicle"  
        tesla-control -ble add-key-request public.pem owner cloud_key;;
      *)
       echo "Invalid Configuration request";;
     esac;;
    
    tesla_ble/command)
     echo "Command $msg requested"
     case $msg in
       wake)
        echo "Waking Car"
        send_command "-domain vcsec $msg";;     
       trunk-open)
        echo "Opening Trunk"
        send_command $msg;;
       trunk-close)
        echo "Closing Trunk"
        send_command $msg;;
       charging-start)
        echo "Start Charging"
        send_command $msg;; 
       charging-stop)
        echo "Stop Charging"
        send_command $msg;;         
       charge-port-open)
        echo "Open Charge Port"
        send_command $msg;;   
       charge-port-close)
        echo "Close Charge Port"
        send_command $msg;;    
       auto-seat-and-climate)
        echo "Start Auto Seat and Climate"
        send_command $msg;;          
       climate-off)
        echo "Stop Climate"
        send_command $msg;;
       charging-stop)
        echo "Stop Climate"
        send_command $msg;;
       flash_lights)
        echo "Flash Lights"
        send_command $msg;;
       frunk-open)
        echo "Open Frunk"
        send_command $msg;;
       honk)
        echo "Honk Horn"
        send_command $msg;;
       lock)
        echo "Lock Car"
        send_command $msg;; 
       unlock)
        echo "Unlock Car"
        send_command $msg;;
       unlock)
        echo "Unlock Car"
        send_command $msg;;
       windows-close)
        echo "Close Windows"
        send_command $msg;;
       windows-vent)
        echo "Vent Windows"
        send_command $msg;; 
       product-info)
        echo "Get Product Info (experimental)"
        send_command $msg;;          
       session-info)
        echo "Get Session Info (experimental)"
        send_command $msg;;  
       *)
        echo "Invalid Command Request";;
      esac;;
      
    tesla_ble/charging-amps)
     echo Set Charging Amps to $msg requested
     # https://github.com/iainbullock/tesla_ble_mqtt_docker/issues/4
     echo First Amp set
     send_command "charging-set-amps $msg"
     sleep 1
     echo Second Amp set
     send_command "charging-set-amps $msg";;
    
    homeassistant/status)
     # https://github.com/iainbullock/tesla_ble_mqtt_docker/discussions/6
     echo "Home Assistant is stopping or starting, re-running auto-discovery setup"
     . /app/discovery.sh;;
     
    *)
     echo "Invalid MQTT topic";;
   esac
  done
}

echo "Setting up auto discovery for Home Assistant"
. /app/discovery.sh

echo "Discard any unread MQTT messages"
mosquitto_sub -E -i tesla_ble_mqtt -h $MQTT_IP -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PWD -t tesla_ble/+ 

echo "Entering listening loop"
while true
do
 listen_to_mqtt
 listen_to_ble
 sleep 2
done
