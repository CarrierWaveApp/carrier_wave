import { Outlet, Link, useNavigate, useLocation } from 'react-router-dom';
import { clearToken } from '../api/client';

const navItems = [
  { to: '/', label: 'Challenges', match: (p: string) => p === '/' || p.startsWith('/challenges') },
  { to: '/programs', label: 'Programs', match: (p: string) => p.startsWith('/programs') },
  { to: '/clubs', label: 'Clubs', match: (p: string) => p.startsWith('/clubs') },
  { to: '/sync', label: 'Sync', match: (p: string) => p.startsWith('/sync') },
  { to: '/achievements', label: 'Achievements', match: (p: string) => p.startsWith('/achievements') },
];

export default function Layout() {
  const navigate = useNavigate();
  const location = useLocation();

  const handleLogout = () => {
    clearToken();
    navigate('/login');
  };

  return (
    <div className="min-h-screen">
      <nav className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between h-16">
            <div className="flex">
              <div className="flex-shrink-0 flex items-center">
                <Link to="/" className="text-xl font-bold text-gray-900">
                  Admin
                </Link>
              </div>
              <div className="hidden sm:ml-6 sm:flex sm:space-x-8">
                {navItems.map((item) => (
                  <Link
                    key={item.to}
                    to={item.to}
                    className={`${
                      item.match(location.pathname)
                        ? 'border-blue-500 text-gray-900'
                        : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                    } inline-flex items-center px-1 pt-1 border-b-2 text-sm font-medium`}
                  >
                    {item.label}
                  </Link>
                ))}
              </div>
            </div>
            <div className="flex items-center">
              <button
                onClick={handleLogout}
                className="text-gray-500 hover:text-gray-700 text-sm font-medium"
              >
                Logout
              </button>
            </div>
          </div>
        </div>
      </nav>

      <main className="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <Outlet />
      </main>
    </div>
  );
}
