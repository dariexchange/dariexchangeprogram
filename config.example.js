// 1) 이 파일을 복사해 이름을 config.js 로 바꾸세요.
// 2) Supabase 대시보드 > Project Settings > API 에서 두 값을 복사해 넣으세요.
//    anon(public) 키는 브라우저에 공개되어도 되는 키입니다. 데이터 보호는 schema.sql 의 접근 규칙(RLS)이 담당합니다.
//    service_role 키는 절대 넣지 마세요.
window.DARI_CONFIG = {
  supabaseUrl: 'https://YOUR-PROJECT-ID.supabase.co',
  supabaseAnonKey: 'YOUR-ANON-PUBLIC-KEY'
};
