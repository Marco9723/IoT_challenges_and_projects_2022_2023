 
#include "Timer.h"
#include "Project1.h"
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

#define TIME0 100     //used in generate/actual send
#define TIME1 300     //used in PAN message sending (pop/push)
#define TIME2 2000     //used in CLIENT connection routine
#define TIME3 10000     //used in CLIENT subscription routine

#define SERVER_IP "127.0.0.1"  // Localhost IP address
#define SERVER_PORT 1234       // Port number for the server

module Project1C @safe() {
  uses {
    /****** INTERFACES *****/
	interface Boot;

    //interfaces for communication
    interface Receive;
    interface AMSend;
    interface SplitControl as AMControl;
	interface Packet;
	    
    interface Random;		//used in generating payload and choosing topics
    	
	//interface for timers
	interface Timer<TMilli> as Timer0;	//used in generate/actual send
	interface Timer<TMilli> as Timer1;	//used in PAN message sending (pop/push)
	interface Timer<TMilli> as Timer2;	//used in CLIENT connection routine
	interface Timer<TMilli> as Timer3;	//used in CLIENT subscription routine
  }
}

implementation {

	// Socket for tcp connection to Node-red
	int sockfd;
    struct sockaddr_in servaddr;
    

  message_t packet;  

  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr; 
   
  //only for CLIENTS
  bool connection = FALSE;								// TRUE if acked
  bool sub_wish[NUM_TOPIC] = {FALSE,FALSE,FALSE};		// TRUE if choosen
  bool sub_done[NUM_TOPIC] = {FALSE,FALSE,FALSE};		// TRUE if acked
  uint8_t num_topic;	// number of topics choosen
  uint8_t num_sub;		// number of subscription acked
  uint8_t topic_pub;	// choosen topic on which could PUB
  
  typedef struct message_list {		//struct linked-list of message to send
      MQTT_msg_t saved_msg;			//packet
      uint16_t dest_id;				//destination
      struct message_list* next;	//next-node
  }   message_list_t;

  message_list_t* message_list = NULL;
  client_list_t client_list[NODES-1];
 
  bool locked; 	  //radio busy or not
  
  //used for PRINT purpose
  const char* msg_name[5] = { [CONNECT] = "CONNECT", [CONNACK] = "CONNACK", [SUBSCRIBE] = "SUBSCRIBE",  [SUBACK] = "SUBACK", [PUBLISH] = "PUBLISH"};
  const char* topic_name[NUM_TOPIC] = { [TEMPERATURE] = "TEMPERATURE", [HUMIDITY] = "HUMIDITY", [LUMINOSITY] = "LUMINOSITY"};
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet);
  
  //manage msg type generation
  void connectPAN();
  void subscribe();   
  void publish();
  
  void choose_topic();
  void init_client_list();
  bool is_empty_message_list(message_list_t** list);
  void push_message(message_list_t** list, MQTT_msg_t msg, uint16_t address);
  uint16_t pop_message(message_list_t** list, MQTT_msg_t* message);
	
  event void Boot.booted() {
    dbg("boot","Application booted.\n");
    call AMControl.start(); 	    
  }
  
  event void AMControl.startDone(error_t err) {
	if (err == SUCCESS) {
		dbg("boot", "NODE %d Radio ON!\n", TOS_NODE_ID);
	    locked = FALSE;
    	if(TOS_NODE_ID==PAN_ADDR){		//if it is the PAN COORD
    		init_client_list();			//init the client list
        	call Timer1.startOneShot(TIME1);
    	}                                
    
    	else{ 	//if CLIENT
    		choose_topic();		//to subscribed and to public
    		call Timer2.startOneShot(TIME2); 
    		}
    } 
    
    else { call AMControl.start(); } //re-try
  }
  
  event void Timer0.fired() {	//Timer triggered to perform the send.
  	actual_send (queue_addr, &queued_packet);	
  	}
 
  event void Timer1.fired() { 	//handling PAN message list
        if(is_empty_message_list(&message_list) == TRUE) {
        	call Timer1.startOneShot(TIME1);
            return;
        } 
        else {	//send a message from its list
        	MQTT_msg_t msg;
        	uint16_t address = pop_message(&message_list, &msg);
        	MQTT_msg_t* payload = (MQTT_msg_t*) call Packet.getPayload(&packet, sizeof(MQTT_msg_t));
        	*payload = msg;
        	generate_send(address, &packet);
        	call Timer1.startOneShot(TIME1); 
        }
	}
  
  event void Timer2.fired() { 	//handling CLIENT connection 
  	if(connection) {         	//already connected 
        call Timer3.startOneShot(TIME3);
        return;
    } 
    else { connectPAN();}	//not already connected
	}

  event void Timer3.fired() {	//handling CLIENT subscription/publish
    if(num_topic == num_sub) {  	//already subscripted on almost one
    	publish();
        return;
	} 
    else { subscribe(); }	//not already subscribed
    }
	
  bool generate_send (uint16_t address, message_t* packet){

  	if (call Timer0.isRunning())
  	{	return FALSE;	}
  	else
  		{
  		queued_packet = *packet;
  		queue_addr = address;
  		call Timer0.startOneShot(TIME0);
  		return TRUE;
  		}    
  }
  
  bool actual_send (uint16_t address, message_t* packet){

	if (locked) {	//if the radio channel is not avaible do nothing
    	return FALSE;  
    	dbg("radio", "NODE %d Radio not avaible\n", TOS_NODE_ID);
    }
    else { 			//else send the message
		if (call AMSend.send(address, packet, sizeof(MQTT_msg_t)) == SUCCESS) 
		{     locked = TRUE;}
    	return TRUE;
    }
  }
  
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	if (&queued_packet == bufPtr && error==SUCCESS) { 
		locked = FALSE;  // if the message is correctly received, free the radio channel
  	} 
  }
                   
  event void AMControl.stopDone(error_t err) {
  	dbg("radio", "NODE %d Radio stopped!\n", TOS_NODE_ID);
  }


  event message_t* Receive.receive(message_t* bufPtr, 
				   void* payload, uint8_t len) {
    	
	if (len != sizeof(MQTT_msg_t)) {
    	dbgerror("radio", "NODE %d Receiving corrupted message\n", TOS_NODE_ID);
    	return bufPtr;	}
    	
    else{
    	MQTT_msg_t* received_msg = (MQTT_msg_t*)payload;	//when a message is received, save payload
    	MQTT_msg_t* msg = (MQTT_msg_t*)call Packet.getPayload(&packet, sizeof(MQTT_msg_t));
    	uint8_t i;

    	switch (received_msg->type)	{
    	
    		case CONNECT:	//solo PAN puo' riceverlo -> answer with CONNACK
      			if(client_list[received_msg->id-1].connected==FALSE){
      				msg->type = CONNACK;
      				client_list[received_msg->id-1].connected = TRUE;	//saving the CLIENT ID in table
      				dbg("connect", "PAN receiving CONNECT from %d\n", received_msg->id);
      				dbg("list", "PAN quequed CONNACK to CLIENT %d\n",received_msg->id);
  					push_message(&message_list, *msg, received_msg->id);	//add message in queque
  				}
      			break;
      		
      		case CONNACK:	//solo CLIENT puo' riceverlo -> set connection 
      			connection = TRUE;
      			dbg("connect", "CLIENT %d receiving CONNACK from PAN\n", TOS_NODE_ID);
      			break;
      			
      		case SUBSCRIBE:	//solo PAN puo' riceverlo -> answer with SUBACK to same CLIENT
      			dbg("subscribe", "PAN receiving SUBSCRIBE from %d for topic %s \n", received_msg->id, topic_name[received_msg->topic]);
 				if(client_list[received_msg->id-1].topic[received_msg->topic]==FALSE){
 					msg->type = SUBACK;
  					msg->topic = received_msg->topic;
  					client_list[received_msg->id-1].topic[msg->topic]=TRUE;
  					dbg("list", "PAN quequed SUBACK to CLIENT %d for TOPIC %s \n",TOS_NODE_ID, topic_name[msg->topic]);
					push_message(&message_list, *msg, received_msg->id);	//add message in queque
				}
      			break;
      			
      		case SUBACK:	//solo CLIENT puo' riceverlo -> set subscription
      			dbg("subscribe", "CLIENT %d receiving SUBACK \n",TOS_NODE_ID);
      			dbg("subscribe", "CLIENT %d is now subscribed on topic %s \n",TOS_NODE_ID, topic_name[received_msg->topic]);
      			num_sub++;	//subscription counter
      			sub_done[received_msg->topic]=TRUE;
      			break;
      			
      		case PUBLISH:	//tutti possono riceverlo
				msg->type = PUBLISH;
				msg->topic = received_msg->topic;
				msg->payload = received_msg->payload;
      		
      		    if(TOS_NODE_ID==PAN_ADDR){	//PAN
      				for (i = 0; i < 8; i++) {    
      					if (client_list[i].topic[msg->topic] == TRUE) {
      					dbg("publish", "PAN forwarding PUBLISH: topic %s, value %d to CLIENT %d\n",topic_name[msg->topic], msg->payload, i+1);
      					push_message(&message_list, *msg, i+1);	
						}
					}
					
					// Send the message to Node-RED TCP node
					dbg("publish", "PAN sending PUB messages to Node-RED\n");
					sockfd = socket(AF_INET, SOCK_STREAM, 0);// Create socket
					if(sockfd == -1)
					{
						dbg("error", "Socket creation failed!\n");
						return bufPtr;
					}
					// Set server address
					servaddr.sin_family = AF_INET;
					servaddr.sin_addr.s_addr = inet_addr(SERVER_IP);
					servaddr.sin_port = htons(SERVER_PORT);
					// Connect to the server
					if(connect(sockfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) != 0)
					{
						dbg("error", "Connection with the server failed!\n");
						close(sockfd);
						return bufPtr;
					}
					// Send the message
					if(send(sockfd, msg, sizeof(MQTT_msg_t), 0) == -1)
					{
						dbg("error", "Failed to send message!\n");
						return bufPtr;
					}
						close(sockfd);
      			}
      			else{	//CLIENT
					dbg("publish", "CLIENT %d receiving PUBLISH: TOPIC %s, value %d \n",TOS_NODE_ID, topic_name[received_msg->topic], received_msg->payload);
					}	
      			break;      				
    	} //close switch
	return bufPtr; }// close else 
}//close receive
 
	void connectPAN() {  
		MQTT_msg_t* msg = (MQTT_msg_t*)call Packet.getPayload(&packet, sizeof(MQTT_msg_t));
  		msg->type = CONNECT;
 		msg->id = TOS_NODE_ID;
  		dbg("connect", "CLIENT %d trying to CONNECT to PANC\n",TOS_NODE_ID); //il PANC dovrà rispondere
  		generate_send(PAN_ADDR, &packet);
  		call Timer2.startOneShot(TIME2);
  	}
  
	void subscribe() {	
			
			MQTT_msg_t* msg = (MQTT_msg_t*)call Packet.getPayload(&packet, sizeof(MQTT_msg_t));
			uint8_t indx=0;
			uint8_t i=0;
			
			//check which of its choosen topic is missing
			for(i=0;i<NUM_TOPIC;i++){
				if(sub_done[indx] == sub_wish[indx])
				{indx++;}
			}
						
	  		msg->type = SUBSCRIBE;
	  		msg->id = TOS_NODE_ID;	//in order to generate the SUBACK its necessary to know the sender	
	    	msg->topic = indx;
	    	
	  		dbg("subscribe", "CLIENT %d sending SUBSCRIBE on %s to PAN\n",TOS_NODE_ID, topic_name[indx]);
	  		generate_send (PAN_ADDR, &packet);
	  		call Timer3.startOneShot(TIME3); //wait for ack
  	}
  	
  	void publish() {
		MQTT_msg_t* msg = (MQTT_msg_t*)call Packet.getPayload(&packet, sizeof(MQTT_msg_t));
		msg->type = PUBLISH;
		msg->id = TOS_NODE_ID;
		msg->payload = call Random.rand16() % 101;
		msg->topic=topic_pub;
		dbg("publish", "CLIENT %d sending PUBLISH: topic %s, value %d\n",TOS_NODE_ID, topic_name[msg->topic], msg->payload);
		generate_send (PAN_ADDR, &packet);
		call Timer3.startOneShot(TIME3); //wait for ack
  	}
  	 	
  	void push_message(message_list_t** list, MQTT_msg_t msg, uint16_t address) {
  	  message_list_t* new_message = (message_list_t*) malloc(sizeof(message_list_t));
  	  new_message->saved_msg = msg;
  	  new_message->dest_id = address;
  	  new_message->next = NULL;	
  	  if (is_empty_message_list(list)) {
      	*list = new_message;
      } 
      else {
        message_list_t* current = *list;
        while (current->next != NULL) {
            current = current->next;
        }
        current->next = new_message;
      }
	}
	bool is_empty_message_list(message_list_t** list) { return *list == NULL;}
	
	uint16_t pop_message(message_list_t** list, MQTT_msg_t* message) {   //extract DESTINATION
       message_list_t* current = *list;
       uint16_t address = current->dest_id;
       *message = current->saved_msg;  
       *list = current->next;
       free(current);
       dbg("list", "PAN pop message to destination %d\n", address);	
       return address;
    }
    
    void choose_topic() {
      	uint8_t i;
      	num_sub=0;
      	num_topic = call Random.rand16()%3;
      	num_topic = num_topic + 1;
      	
      	topic_pub = call Random.rand16()%3;		//topic on which the CLIENT could PUB (in future)
      
      	// randomly chooses how many topics to want and which ones
      	while((sub_wish[0]+sub_wish[1]+sub_wish[2])!=num_topic)
      	{
      		uint8_t new_topic = call Random.rand16()%3;
      		sub_wish[new_topic] = TRUE;
      	} 
      	dbg("boot", "CLIENT %d could PUB on TOPIC %s \n", TOS_NODE_ID, topic_name[topic_pub]);
      
		for(i=0; i<NUM_TOPIC; i++)
      	{
			if(sub_wish[i])
			{
				dbg("boot", "CLIENT %d would like to SUB on TOPIC %s\n", TOS_NODE_ID, topic_name[i]);
			}
		}
    }
    
    
   void init_client_list() {
    	uint8_t i;	//counter of NODE
    	uint8_t j;	//counter of TOPIC
    	dbg("boot", "PAN INIT CLIENT LIST\n");
    	
        for(i = 0; i < NODES; i++) {
        	client_list[i].connected = FALSE;
        	for(j=0; j < NUM_TOPIC; j++) {
            	client_list[i].topic[j] = FALSE;
            }
        }
    }
}






