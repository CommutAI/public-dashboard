import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({
    plugins: [react()],
    build: {
        chunkSizeWarningLimit: 1000,
        rollupOptions: {
            output: {
                manualChunks: (id) => {
                    if (id.includes('node_modules')) {
                        if (id.includes('react-leaflet') || id.includes('leaflet')) {
                            return 'vendor-map';
                        }
                        if (id.includes('@supabase/supabase-js')) {
                            return 'vendor-supabase';
                        }
                    }
                },
            },
        },
    },
    server: {
        port: 3009,
        host: '0.0.0.0',
    },
});
