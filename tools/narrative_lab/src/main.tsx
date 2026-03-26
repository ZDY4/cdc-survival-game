import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./styles.css";

const splash = document.getElementById("boot-splash");

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);

requestAnimationFrame(() => {
  splash?.classList.add("boot-splash-hidden");
  window.setTimeout(() => {
    splash?.remove();
  }, 180);
});
