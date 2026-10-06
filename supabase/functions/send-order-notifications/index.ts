import { createClient } from 'npm:@supabase/supabase-js@2.117.2';
import { GoogleAuth } from 'npm:google-auth-library@9.15.1';
import { createDispatchHandler, notificationPayload } from './handler.ts';

let client: ReturnType<typeof createClient>;
const database=()=>client??=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  {auth:{persistSession:false,autoRefreshToken:false}});
async function rpc(name:string,params:Record<string,unknown>={}) {
  const {data,error}=await database().rpc(name,params); if(error) throw new Error('Database request failed'); return data;
}
let credentials:any;
function configured() {
  try {
    credentials=JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')??'null');
    return credentials?.type==='service_account'&&typeof credentials?.project_id==='string'&&
      /^[a-z0-9-]+$/.test(credentials.project_id)&&typeof credentials.client_email==='string'&&typeof credentials.private_key==='string';
  } catch (_) {return false;}
}

Deno.serve(createDispatchHandler({
  authorize:async(secret)=>await rpc('authorize_push_dispatch',{requested_secret:secret})===true,
  configured,
  accessToken:async()=> {
    const auth=new GoogleAuth({credentials,scopes:['https://www.googleapis.com/auth/firebase.messaging']});
    const token=await auth.getAccessToken();if(!token) throw new Error('Provider authorization failed');return token;
  },
  claim:()=>rpc('claim_notification_batch',{requested_limit:10}),
  devices:async(user)=> {
    const {data,error}=await database().from('device_tokens').select('id,token,user_id,sound_enabled').eq('user_id',user);
    if(error) throw new Error('Device lookup failed');return data??[];
  },
  current:async(notification)=> {
    const {data,error}=await database().from('orders').select('user_id,order_status').eq('id',notification.data.order_id).maybeSingle();
    if(error) throw new Error('Order lookup failed');return data?.user_id===notification.user_id&&data?.order_status===notification.data.status;
  },
  acknowledge:(n,device)=>rpc('acknowledge_notification_device',{requested_id:n.id,requested_claim:n.claim_token,requested_device:device}),
  finish:(n,success,code)=>rpc('finish_notification_dispatch',{requested_id:n.id,requested_claim:n.claim_token,successful:success,error_code:code}),
  removeDevice:async(token)=> {const {error}=await database().from('device_tokens').delete().eq('token',token);if(error) throw new Error('Token cleanup failed');},
  send:async(access,notification,device)=> {
    const response=await fetch(`https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`,{
      method:'POST',headers:{Authorization:`Bearer ${access}`,'Content-Type':'application/json'},
      body:JSON.stringify(notificationPayload(notification,device)),signal:AbortSignal.timeout(5000)});
    if(response.ok) return {ok:true,unregistered:false};
    let details:any;try {details=await response.json();} catch (_) {}
    return {ok:false,unregistered:details?.error?.details?.some((d:any)=>d.errorCode==='UNREGISTERED')??false};
  },
  now:()=>Date.now(),
}));
