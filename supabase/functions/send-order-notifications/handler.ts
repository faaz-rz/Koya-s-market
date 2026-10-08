import { json } from '../_shared/http.ts';

export interface DispatchDependencies {
  authorize(secret: string): Promise<boolean>;
  configured(): boolean;
  accessToken(): Promise<string>;
  projectId?(): string;
  validate?(accessToken: string, deviceToken: string): Promise<boolean>;
  testDelivery?(accessToken: string, deviceToken: string): Promise<boolean>;
  claim(): Promise<any[]>;
  devices(user: string): Promise<any[]>;
  current(notification: any): Promise<boolean>;
  acknowledge(notification: any, device: string): Promise<boolean>;
  finish(notification: any, success: boolean, code: string | null): Promise<boolean>;
  removeDevice(token: string): Promise<void>;
  send(accessToken: string, notification: any, device: any): Promise<{ok:boolean;unregistered:boolean}>;
  now(): number;
}

export function notificationPayload(notification: any, device: any) {
  const data = { order_id:String(notification.data.order_id), user_id:String(notification.user_id),
    status:String(notification.data.status), event_id:String(notification.id) };
  const sound = device.sound_enabled !== false;
  return { message:{token:device.token,notification:{title:'Koya Stores',body:notification.body},data,
    android:{priority:'high',ttl:'3600s',notification:{tag:notification.id,
      notification_priority:'PRIORITY_HIGH',visibility:'PUBLIC',
      default_vibrate_timings:sound,
      channel_id:sound?'customer_order_updates_v1':'customer_order_updates_silent_v1',
      ...(sound?{sound:'default'}:{}),icon:'ic_stat_order'}},
    apns:{headers:{'apns-priority':'10','apns-push-type':'alert','apns-collapse-id':notification.id},
      payload:{aps:{...(sound?{sound:'default'}:{}), 'thread-id':'koyas-orders'}}}} };
}

export function createDispatchHandler(deps: DispatchDependencies) {
  return async(request: Request): Promise<Response> => {
    if(request.method!=='POST') return json({error:'Method not allowed'},405);
    const secret=request.headers.get('x-koyas-webhook-secret')??'';
    if(secret.length<32||secret.length>256) return json({error:'Unauthorized'},401);
    const unfinished = new Map<string, any>();
    try {
      if(!await deps.authorize(secret)) return json({error:'Unauthorized'},401);
      if(!deps.configured()) return json({error:'Push is not configured'},503);
      const access=await deps.accessToken();
      if(request.headers.get('x-koyas-test-delivery')==='true') {
        // Authorized operational QA only: a fixed test message, never queue work.
        const device=request.headers.get('x-koyas-validation-token');
        if(!device || device.length>4096) return json({error:'A QA device is required'},400);
        if(!deps.testDelivery || !await deps.testDelivery(access,device)) {
          return json({error:'Provider test delivery failed'},503);
        }
        return json({sent:true,project_id:deps.projectId?.()??null,claimed:0});
      }
      if(request.headers.get('x-koyas-check-config')==='true') {
        // Private operational check: never claims queue work or sends a message.
        // Google validate_only verifies API/IAM access against a QA device token.
        const device=request.headers.get('x-koyas-validation-token');
        if(device && (device.length>4096 || !deps.validate || !await deps.validate(access,device))) {
          return json({error:'Provider validation failed'},503);
        }
        return json({ready:true,project_id:deps.projectId?.()??null,
          provider_validated:!!device,claimed:0});
      }
      const queue=await deps.claim();
      for(const notification of queue) unfinished.set(notification.id,notification);
      const deadline=deps.now()+40000;
      let delivered=0;
      for(const notification of queue) {
        let successful=true;
        let code:string|null=null;
        if(!await deps.current(notification)) {
          await deps.finish(notification,true,'obsolete'); unfinished.delete(notification.id); continue;
        }
        const acknowledged=new Set(notification.delivered_device_ids??[]);
        const devices=await deps.devices(notification.user_id);
        for(const device of devices) {
          if(acknowledged.has(device.id)) continue;
          if(deps.now()>deadline) {successful=false;code='budget';break;}
          if(device.user_id!==notification.user_id) continue;
          const result=await deps.send(access,notification,device);
          if(result.unregistered) await deps.removeDevice(device.token);
          else if(!result.ok) {successful=false;code='provider_retry';continue;}
          if(!await deps.acknowledge(notification,device.id)) {successful=false;code='lost_lease';break;}
        }
        const completed=await deps.finish(notification,successful,code);
        if(!completed) throw new Error('lost lease');
        unfinished.delete(notification.id);
        if(successful) delivered++;
        if(deps.now()>deadline) break;
      }
      return json({claimed:queue.length,completed:delivered});
    } catch (_) {
      // Provider responses can contain tokens. No provider error is logged.
      return json({error:'Notification dispatch failed'},503);
    } finally {
      for(const notification of unfinished.values()) {
        try {await deps.finish(notification,false,'interrupted');} catch (_) {}
      }
    }
  };
}
