#ifndef PROJECT1_H
#define PROJECT1_H

#define PAN_ADDR 9
#define AM_RADIO_COUNT_MSG 10
#define NODES 9
#define NUM_TOPIC 3


typedef nx_struct MQTT_msg {
	nx_uint8_t type; 
	nx_uint16_t id;
	nx_uint8_t topic;
	nx_uint16_t payload;
} MQTT_msg_t;

typedef nx_struct client_table {
    nx_uint8_t connected;
    nx_uint8_t topic[NUM_TOPIC];
} client_table_t;

typedef client_table_t client_list_t;

enum {
  	CONNECT = 0,
  	CONNACK = 1,
  	SUBSCRIBE = 2,
  	SUBACK = 3,
  	PUBLISH = 4
  	};
  	
enum { 	
  	TEMPERATURE = 0,
  	HUMIDITY = 1,
  	LUMINOSITY = 2
  	};

#endif
