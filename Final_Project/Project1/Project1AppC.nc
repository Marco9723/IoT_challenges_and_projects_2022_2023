

#include "Project1.h"


configuration Project1AppC {}
implementation {
/****** COMPONENTS *****/
  components MainC, Project1C as App;
  //add the other components here
 
  components new AMSenderC(AM_RADIO_COUNT_MSG);
  components new AMReceiverC(AM_RADIO_COUNT_MSG);
  components new TimerMilliC() as Timer0;
  components new TimerMilliC() as Timer1;
  components new TimerMilliC() as Timer2;
  components new TimerMilliC() as Timer3;
  components ActiveMessageC;
  components RandomC;
  
  
  /****** INTERFACES *****/
  //Boot interface
  App.Boot -> MainC.Boot; 
  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.AMControl -> ActiveMessageC;
  App.Timer0 -> Timer0;
  App.Timer1 -> Timer1;
  App.Timer2 -> Timer2;
  App.Timer3 -> Timer3;
  App.Packet -> AMSenderC;
  App.Random -> RandomC;
  
}
