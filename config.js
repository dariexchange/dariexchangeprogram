// DARI 실제 운영 서버(Supabase) 연결 설정
// Publishable(공개) 키는 브라우저에 공개되어도 되는 키입니다. 데이터 보호는 데이터베이스 접근 규칙(RLS)이 담당합니다.
// secret / service_role 키는 절대 이 파일에 넣지 마세요.
window.DARI_CONFIG = {
  supabaseUrl: 'https://gupysbsikngfpuucffwb.supabase.co',
  supabaseAnonKey: 'sb_publishable_6PMwLkhjy4Zi3U0DhT7Yhw_IA_6Llsu'
};
