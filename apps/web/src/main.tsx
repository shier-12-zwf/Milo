import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// 注：不使用 StrictMode，避免开发环境下对话初始化副作用被执行两次
createRoot(document.getElementById('root')!).render(<App />)
