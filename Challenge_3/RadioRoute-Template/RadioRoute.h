

#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H

typedef nx_struct radio_route_msg {
  nx_uint16_t type; 
  nx_uint16_t sender; 
  nx_uint16_t destination; 
  nx_uint16_t value; 
  nx_uint16_t node_requested;
  nx_uint16_t cost; 
} radio_route_msg_t;

typedef nx_struct routing_table {  
  nx_uint16_t destination; 
  nx_uint16_t next_hop; 
  nx_uint16_t cost; 
} routing_table_t;

enum {
  AM_RADIO_COUNT_MSG = 10,
  PERSON_CODE=10528650
};

#endif
