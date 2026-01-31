import { Routes, Route, useNavigate, useLocation } from 'react-router-dom';
import { NavMenu, TitleBar } from '@shopify/app-bridge-react';

// Pages
import Dashboard from './pages/Dashboard';
import ProductPagesList from './pages/ProductPagesList';
import ProductPageShow from './pages/ProductPageShow';
import ProductPagesNew from './pages/ProductPagesNew';
import IssuesList from './pages/IssuesList';
import IssueShow from './pages/IssueShow';
import ScansList from './pages/ScansList';
import ScanShow from './pages/ScanShow';
import Settings from './pages/Settings';

function App() {
  const navigate = useNavigate();
  const location = useLocation();

  // Get page title based on current route
  const getPageTitle = () => {
    const path = location.pathname;
    if (path === '/' || path === '/home') return 'Dashboard';
    if (path === '/product_pages/new') return 'Add Products';
    if (path.startsWith('/product_pages/')) return 'Product Details';
    if (path === '/product_pages') return 'Monitored Pages';
    if (path.startsWith('/issues/')) return 'Issue Details';
    if (path === '/issues') return 'Issues';
    if (path.startsWith('/scans/')) return 'Scan Details';
    if (path === '/scans') return 'Scan History';
    if (path === '/settings') return 'Settings';
    return 'PDP Diagnostics';
  };

  return (
    <>
      <NavMenu>
        <a href="/" rel="home">PDP Diagnostics</a>
        <a href="/">Dashboard</a>
        <a href="/product_pages">Monitored Pages</a>
        <a href="/issues">Issues</a>
        <a href="/scans">Scan History</a>
        <a href="/settings">Settings</a>
      </NavMenu>

      <TitleBar title={getPageTitle()} />

      <s-page>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/home" element={<Dashboard />} />
          <Route path="/product_pages" element={<ProductPagesList />} />
          <Route path="/product_pages/new" element={<ProductPagesNew />} />
          <Route path="/product_pages/:id" element={<ProductPageShow />} />
          <Route path="/issues" element={<IssuesList />} />
          <Route path="/issues/:id" element={<IssueShow />} />
          <Route path="/scans" element={<ScansList />} />
          <Route path="/scans/:id" element={<ScanShow />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </s-page>
    </>
  );
}

export default App;
