
 
#include "RadioRoute.h"


configuration RadioRouteAppC {}
implementation {
/****** COMPONENTS *****/
  components MainC, RadioRouteC as App, LedsC;
  //add the other components here
 
  components new AMSenderC(AM_RADIO_COUNT_MSG);
  components new AMReceiverC(AM_RADIO_COUNT_MSG);
  components new TimerMilliC() as Timer0;
  components new TimerMilliC() as Timer1;
  components ActiveMessageC;
  
  
  
  /****** INTERFACES *****/
  //Boot interface
  App.Boot -> MainC.Boot; 
  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.AMControl -> ActiveMessageC;
  App.Leds -> LedsC;
  App.Timer0 -> Timer0;
  App.Timer1 -> Timer1;
  App.Packet -> AMSenderC;
  
  /****** Wire the other interfaces down here *****/

}


