import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'

// 確実にマウントを実行
const rootElement = document.getElementById('root');

if (rootElement) {
  ReactDOM.createRoot(rootElement).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
} else {
  console.error("Root element not found! HTMLの <div id='root'> が存在するか確認してください。");
}