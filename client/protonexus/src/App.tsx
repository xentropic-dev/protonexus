import { useState } from "react";
import reactLogo from "./assets/react.svg";
import viteLogo from "/vite.svg";
import "./App.css";

function App() {
  const [count, setCount] = useState(0);
  const [info, setInfo] = useState({ uptime: 0, count: 0 });

  setInterval(() => {
    fetch("/api/info")
      .then((response) => response.json())
      .then((data) => {
        setInfo(data);
      })
      .catch((error) => {
        console.error("Error fetching info:", error);
      });
  }, 5000); // Update every 5 seconds

  // fetch data from /api/info
  // do this in the best way possible
  // and display the result in the UI
  // the info is a object with uptime and count properties
  // update every 5 seconds

  return (
    <>
      <div>
        <a href="https://vite.dev" target="_blank">
          <img src={viteLogo} className="logo" alt="Vite logo" />
        </a>
        <a href="https://react.dev" target="_blank">
          <img src={reactLogo} className="logo react" alt="React logo" />
        </a>
      </div>
      <h1>Vite + React</h1>
      <div className="card">
        <button onClick={() => setCount((count) => count + 1)}>
          count is {count}
        </button>
        <p>
          Edit <code>src/App.tsx</code> and save to test HMR
        </p>
      </div>
      <p className="read-the-docs">
        Click on the Vite and React logos to learn more
      </p>
      <div>
        <h2>API Info</h2>
        <p>Uptime: {info.uptime / 1000} seconds</p>
        <p>Count: {info.count}</p>
      </div>
    </>
  );
}

export default App;
