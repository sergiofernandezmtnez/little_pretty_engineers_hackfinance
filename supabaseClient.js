import { createClient } from '@supabase/supabase-js'

// Aquí van tus credenciales reales (las que copiaste del panel de Supabase)
const supabaseUrl = 'https://jvytaiwnyjyvxjpjhcce.supabase.co'
const supabaseKey = 'sb_publishable_0L2c8fZN37Em5oVgqmy9Ww_PcePVLil'

export const supabase = createClient(supabaseUrl, supabaseKey)
