/** @type {import('tailwindcss').Config} */
// Carrier Wave brand tokens (dark console aesthetic — matches the marketing
// site + design-language.md): near-black surfaces, a blue accent, Outfit for
// UI and IBM Plex Mono for the technical fields (callsigns/freq/RST/grid/time).
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        cw: {
          bg: '#0e0f11',
          surface: '#131518',
          surface2: '#1a1d21',
          border: '#1f2328',
          border2: '#2a2f38',
          text: '#c9cdd6',
          dim: '#666c7a',
          xdim: '#35393f',
          blue: '#4a8cff',
          blue2: '#3a7aee',
          white: '#f2f4f8',
          green: '#34d399',
          red: '#f26d6d',
          amber: '#e0a458',
        },
      },
      fontFamily: {
        sans: ['Outfit', 'ui-sans-serif', 'system-ui', 'sans-serif'],
        mono: ['"IBM Plex Mono"', 'ui-monospace', 'SFMono-Regular', 'monospace'],
      },
    },
  },
  plugins: [],
};
