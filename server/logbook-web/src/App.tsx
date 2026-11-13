import { Navigate, Route, Routes } from 'react-router-dom';
import { useAppState } from './state/AppState';
import LoginPage from './pages/LoginPage';
import UnlockPage from './pages/UnlockPage';
import LogbookPage from './pages/LogbookPage';
import SpotsPage from './pages/SpotsPage';

// Two gates in front of the logbook: authentication (tokens) then unlock (data
// key). Each redirects to the step the user still owes.
export default function App() {
  const { loggedIn, dataKey } = useAppState();

  return (
    <div className="min-h-screen bg-cw-bg text-cw-text">
      <Routes>
        <Route
          path="/login"
          element={loggedIn ? <Navigate to="/" replace /> : <LoginPage />}
        />
        <Route
          path="/unlock"
          element={
            !loggedIn ? (
              <Navigate to="/login" replace />
            ) : dataKey ? (
              <Navigate to="/" replace />
            ) : (
              <UnlockPage />
            )
          }
        />
        {/* Spots need login only — no decrypted data is involved. */}
        <Route
          path="/spots"
          element={!loggedIn ? <Navigate to="/login" replace /> : <SpotsPage />}
        />
        <Route
          path="/"
          element={
            !loggedIn ? (
              <Navigate to="/login" replace />
            ) : !dataKey ? (
              <Navigate to="/unlock" replace />
            ) : (
              <LogbookPage />
            )
          }
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </div>
  );
}
