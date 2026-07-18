import { Navigate, Route, Routes } from 'react-router-dom';
import Layout from './components/Layout';
import ProtectedRoute from './components/ProtectedRoute';
import LoginPage from './pages/LoginPage';
import RegisterOrgPage from './pages/RegisterOrgPage';
import DashboardPage from './pages/DashboardPage';
import EmployeesPage from './pages/EmployeesPage';
import VehiclesPage from './pages/VehiclesPage';
import RidesPage from './pages/RidesPage';
import PricingPage from './pages/PricingPage';
import OrganizationPage from './pages/OrganizationPage';

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/register" element={<RegisterOrgPage />} />
      <Route
        element={
          <ProtectedRoute>
            <Layout />
          </ProtectedRoute>
        }
      >
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={<DashboardPage />} />
        <Route path="/employees" element={<EmployeesPage />} />
        <Route path="/vehicles" element={<VehiclesPage />} />
        <Route path="/rides" element={<RidesPage />} />
        <Route path="/pricing" element={<PricingPage />} />
        <Route path="/organization" element={<OrganizationPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  );
}
