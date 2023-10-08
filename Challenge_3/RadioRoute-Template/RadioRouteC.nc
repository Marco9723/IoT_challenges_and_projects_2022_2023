
/*
*	IMPORTANT:
*	The code will be avaluated based on:
*		Code design  
*
*/
 
 
#include "Timer.h"
#include "RadioRoute.h"


module RadioRouteC @safe() {
  uses {
  
    /****** INTERFACES *****/
	interface Boot;

    //interfaces for communication
    interface Receive;
    interface AMSend;
    interface SplitControl as AMControl;
    interface Packet;
	//interface for timers
	interface Timer<TMilli> as Timer0;
	interface Timer<TMilli> as Timer1;
	//interface for LED
	interface Leds;
    //other interfaces, if needed
    
  }
}
implementation {

  message_t packet;
  routing_table_t rt[6];  //routing table defined as array of 6 structs (possible destinations), in which each field is inits set to 0
  
  
  
  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr;
  uint16_t time_delays[7]={61,173,267,371,479,583,689}; //Time delay in milli seconds
  
  // global variables to extract the digits of the person code
  int person_code_index=8;
  int PERSON_CODE = 10528650;
  
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;
    
  bool locked;
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  
  // other functions defined
  void send_data_1to7(); 
  int power(int base, int exp);
  
   
  bool generate_send (uint16_t address, message_t* packet, uint8_t type){
  /*
  * 
  * Function to be used when performing the send after the receive message event.
  * It store the packet and address into a global variable and start the timer execution to schedule the send.
  * It allow the sending of only one message for each REQ and REP type
  * @Input:
  *		address: packet destination address
  *		packet: full packet to be sent (Not only Payload)
  *		type: payload message type
  *
  * MANDATORY: DO NOT MODIFY THIS FUNCTION
  */

  	if (call Timer0.isRunning()){
  		return FALSE;
  	}else{
  	if (type == 1 && !route_req_sent ){
  		route_req_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 2 && !route_rep_sent){
  	  	route_rep_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 0){
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;	
  	}
  	}
  	return TRUE;
  }
  
  event void Timer0.fired() {
  	/*
  	* Timer triggered to perform the send.
  	* MANDATORY: DO NOT MODIFY THIS FUNCTION
  	*/
  	actual_send (queue_addr, &queued_packet);
  	
  }
  
  bool actual_send (uint16_t address, message_t* packet){
    
    if (locked) {
        //if the radio channel is not avaible do nothing
    	return FALSE;  
    	dbg("radio_send", "NODE %d Radio not avaible\n", TOS_NODE_ID);
    }
    else { 
		if (call AMSend.send(address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {   
		//else send the message
		dbg("radio_send", "NODE %d Sending packet to %d\n", TOS_NODE_ID, address);	
		locked = TRUE;
      }
      return TRUE;
    }
	  
  }
  
  // boot the application and after five seconds start Timer1 to send the DATA message
  event void Boot.booted() {              
    dbg("boot","Application booted.\n");
    call AMControl.start();  
    call Timer1.startOneShot(5000);
  }
  
  // if the booting has been successful start the radio communication, otherwise retry
  event void AMControl.startDone(error_t err) {
	if (err == SUCCESS) {
    	dbg("radio","NODE %d radio ON!\n", TOS_NODE_ID);
    	dbg("led", "NODE %d led STATUS: %u%u%u \n", TOS_NODE_ID, call Leds.get() & LEDS_LED0, (call Leds.get() & LEDS_LED1)/2, (call Leds.get() & LEDS_LED2)/4);                                 
    }
    else {
    	dbgerror("radio", "Radio failed to start, retrying...\n");
    	call AMControl.start();  
    }
  }
  
  // to stop the radio communication
  event void AMControl.stopDone(error_t err) {
  	dbg("radio", "Radio stopped!\n");
  }
  
  event void Timer1.fired() {
	/*
	* Implement here the logic to trigger the Node 1 to send the first REQ packet
	*/
	if(TOS_NODE_ID==1){
		dbg("timer", "timer1 fired for NODE %d\n", TOS_NODE_ID);
		send_data_1to7();      //function to send DATA message from 1 to 7
		}	
  }

  event message_t* Receive.receive(message_t* bufPtr, 
				   void* payload, uint8_t len) {
	/*
	* Parse the receive packet.
	* Implement all the functionalities
	* Perform the packet send using the generate_send function if needed   
	* Implement the LED logic and print LED status on Debug
	*/	
    if (len != sizeof(radio_route_msg_t)) {
    	dbgerror("radio_rec", "NODE %d Receiving corrupted message\n", TOS_NODE_ID);
    	return bufPtr;
    	}
    else {
		int led_index=((PERSON_CODE/(power(10,person_code_index -1)))%10)%3;  //extract led_index
        radio_route_msg_t* received_msg = (radio_route_msg_t*)payload;        //when a message is received, save payload in received_msg  
        
        //algorithm to extract digits' indexes from PERSON_CODE at each received message
        dbg("led", "NODE %d led index: %d\n",TOS_NODE_ID, led_index);
      	person_code_index--;
        
        //round robin cycle
    	if(person_code_index==0){
      		person_code_index=8;
    	}
    	  
      	switch (led_index) {
      		case 0: 
      			call Leds.led0Toggle();   //toggle led 0 if led_index=0
      			break;
      		case 1: 
      			call Leds.led1Toggle();   //toggle led 1 if led_index=1
      			break;
      		case 2: 
      			call Leds.led2Toggle();   //toggle led 2 if led_index=2
      			break;
  		}
  		
  		//print leds' status dividing each digit of the bitmask by its most significant value
  		dbg("led", "NODE %d led STATUS: %u%u%u \n", TOS_NODE_ID, call Leds.get() & LEDS_LED0, (call Leds.get() & LEDS_LED1)/2, (call Leds.get() & LEDS_LED2)/4);
      	      
    
    if(received_msg->type==0){
 	    //if a DATA message is received, transmit it HOP BY HOP
	 	bool check=FALSE;
		int i;
		dbg("radio_rec", "NODE %d receiving DATA msg\n", TOS_NODE_ID);
		//check in the routing table if the destination is present
		for (i = 0; i < 6; i++) {     
			if (rt[i].destination == received_msg->destination) {   
				check=TRUE;
				break;
				}	
		}
		
		// if it is present, generate the same DATA message and send it to the next hop 
		if(check==TRUE){		
		   radio_route_msg_t* data_msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
		   data_msg->type=0;
		   data_msg->sender=received_msg->sender;  
		   data_msg->destination=received_msg->destination;
		   data_msg->value=received_msg->value;
		   dbg("msg_gen", "NODE %d generating DATA msg to %d\n", TOS_NODE_ID, rt[i].next_hop);
		   generate_send (rt[i].next_hop, &packet, data_msg->type);  

		   }

    	
    }
      
      
    if (received_msg-> type == 1) {     
        // if a ROUTE_REQ message is received
    	dbg("radio_rec", "NODE %d receiving REQUEST msg\n", TOS_NODE_ID);
    	//if the node requested is itself
    	if (received_msg-> node_requested == TOS_NODE_ID) {    
            //reply in broadcast with a ROUTE_REPLY, setting the ROUTE_REPLY cost to 1	
    		radio_route_msg_t* sent_msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
            sent_msg->type=2;
            sent_msg->cost=1;
			sent_msg->sender=TOS_NODE_ID;
			sent_msg->node_requested=TOS_NODE_ID;
			dbg("msg_gen", "NODE %d generating in broadcast a ROUTE_REPLY msg\n", TOS_NODE_ID);
			generate_send (AM_BROADCAST_ADDR, &packet, sent_msg->type);  
			    	
    	}
    	else{  
    	    bool check=FALSE;
    	    int i;
    	    // check if the node requested is in my routing table
      		for (i = 0; i < 6; i++) {    
      			if (rt[i].destination == received_msg-> node_requested) {   
  					check=TRUE;
  					break;
					}	
			}
			
			//if the node requested is in my routing table
			if(check==TRUE){   
				//reply in broadcast with a ROUTE_REPLY, setting the ROUTE_REPLY cost to the cost in my routing table + 1
				radio_route_msg_t* sent_msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
				sent_msg->type=2;
            	sent_msg->cost=rt[i].cost +1;
				sent_msg->sender=TOS_NODE_ID;
				sent_msg->node_requested=TOS_NODE_ID;
				dbg("msg_gen", "NODE %d generating in broadcast a ROUTE_REPLY msg\n", TOS_NODE_ID);
				generate_send (AM_BROADCAST_ADDR, &packet, sent_msg->type);
				
			}
			
			//if the node requested is NOT in my routing table
			else{
				//broadcast it if the ROUTE_REQ is a new one (requesting for a node not in my routing table and not me)
				radio_route_msg_t* sent_rqs= (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
				sent_rqs->type=1;
				sent_rqs->node_requested=received_msg->node_requested;
				dbg("msg_gen", "NODE %d generating in broadcast a ROUTE_REQ msg\n", TOS_NODE_ID);
				generate_send (AM_BROADCAST_ADDR, &packet, sent_rqs->type);	
			}
  
    	}
    }
    if (received_msg-> type == 2) {
    	// if a ROUTE_REPLY message is received
    	dbg("radio_rec", "NODE %d receiving REPLY msg\n", TOS_NODE_ID);
    	// if I am the requested node in the REPLY do nothing
  		if (received_msg-> node_requested == TOS_NODE_ID) { } 
  		else{
  		    bool check_empty=FALSE;   //FALSE=empty routing table
  		    bool check_cost=FALSE;    //FALSE=the new cost is NOT lower than my current cost   
  		    int i;  
  		    int j;
  		    
  		    // check if the routing table does not have entry
  			for (i = 0; i < 6; i++) {
  				if(rt[i].cost!=0 ){
  					check_empty=TRUE;
  					break;
  				}
  			}
  			
			// if the routing table is not empty, check if the new cost is lower than my current cost
  			if(check_empty==TRUE){
	  			for (j = 0; j < 6; j++) {     
		  			if (rt[i].destination == received_msg-> node_requested) { 
		  				if(received_msg->cost<rt[i].cost) { 
	  						check_cost=TRUE;
	  						break;
						}
					}	
				}
  			}
  			
  			// if my table does not have entry OR if the new cost is lower than my current cost
  			if(check_empty==FALSE || check_cost==TRUE){
  				
  				// if my table does not have entry
	  			if(check_empty==FALSE){   
	  			    
	  				radio_route_msg_t* sent_rep= (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
	  			    
	  			    //update routing table in position 0 because it is empty
	  				rt[0].destination=received_msg->node_requested;             
					rt[0].cost=received_msg->cost;
					rt[0].next_hop=received_msg->sender;
					
					//forward the ROUTE_REPLY in broadcast by incrementing its cost by 1
				    sent_rep->type=2;
		        	sent_rep->cost=received_msg->cost +1;  
					sent_rep->sender=TOS_NODE_ID;
					sent_rep->node_requested=received_msg->node_requested;
					dbg("msg_gen", "NODE %d generating in broadcast a ROUTE_REPLY msg\n", TOS_NODE_ID);		
					generate_send (AM_BROADCAST_ADDR, &packet, received_msg->type);
					// if the node receiving the ROUTE_REPLY is node 1, send the DATA message towards 7
					if (TOS_NODE_ID ==1){
  						send_data_1to7();
  						}
	  			
	  			}
		
	  			// if the new cost is lower than my current cost
				if(check_cost==TRUE){  
					
					//update routing table
					rt[i].destination=received_msg->node_requested;               
					rt[i].cost=received_msg->cost;
					rt[i].next_hop=received_msg->sender;
				    
				    //forward the ROUTE_REPLY in broadcast by incrementing its cost by 1
		        	received_msg->cost=received_msg->cost +1;  
					received_msg->sender=TOS_NODE_ID;	
					dbg("msg_gen", "NODE %d generating in broadcast a ROUTE_REPLY msg\n", TOS_NODE_ID);
					generate_send (AM_BROADCAST_ADDR, &packet, received_msg->type);
					// if the node receiving the ROUTE_REPLY is node 1, send the DATA message towards 7
					if (TOS_NODE_ID ==1){
  						send_data_1to7();
  						}
	  			
	  			}
	  		}
  			else{
  				// if the node receiving the ROUTE_REPLY is node 1, send the DATA message towards 7
  				if (TOS_NODE_ID ==1){
  				send_data_1to7();
				}
  			}			
			}	
		}
		return bufPtr;								
		}
	}   

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	if (&queued_packet == bufPtr) { 
      locked = FALSE;  // if the message is correctly received, free the radio channel
  }
}

void send_data_1to7() {
	radio_route_msg_t* msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
		
	bool check=FALSE;
    int dest=7;
    int i; 
    
    // check in the routing table if the destination is present	
  	for(i = 0; i < 6; i++){   
  		if (rt[i].destination == dest) {   
			check=TRUE;
			break;
			}	
		}
	dbg("msg_gen", "NODE %d trying to send a DATA msg to destination %d\n",TOS_NODE_ID,dest);
		
	if(check==TRUE){  
		// DATA message (hop-by-hop) if node 7 is in the routing table  
		msg->type=0;
		msg->sender=TOS_NODE_ID;
		msg->destination=dest;
		msg->value=5;
		dbg("msg_gen", "NODE %d generating DATA msg to %d\n", TOS_NODE_ID, rt[i].next_hop);	
		generate_send (rt[i].next_hop, &packet, msg->type); 			
	}
	else{ 
		// ROUTE_REQ message in broadcast              
		dbg("msg_gen", "NODE %d: destination %d not in ROUTING TABLE \n", TOS_NODE_ID, dest);
		msg->type=1;
		msg->node_requested=dest;	
		dbg("msg_gen", "NODE %d generating in broadcast a ROUTE_REQ msg\n", TOS_NODE_ID);
		generate_send (AM_BROADCAST_ADDR, &packet, msg->type); 	
	}


}

//function to calculate the power of a number
	int power(int base, int exp) {
    	int result = 1;
   		while(exp) { result *= base; exp--; }
    	return result;
	}
 
}   

