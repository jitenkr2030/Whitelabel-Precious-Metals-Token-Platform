/**
 * Whitelabel Token Platform Mobile App
 * React Native Implementation
 * 
 * This is the main mobile application that gets white-labeled for each client:
 * - Jewellers
 * - Gold/Silver dealers  
 * - Bullion traders
 * - Vault companies
 * - NBFCs
 * - Loan apps
 * - Fintech apps
 * - Crypto exchanges
 */

import React, { useState, useEffect } from 'react';
import {
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  TextInput,
  ScrollView,
  Alert,
  ActivityIndicator,
  Dimensions,
  StatusBar,
  Image,
  FlatList,
  Modal
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { NavigationContainer } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import Icon from 'react-native-vector-icons/MaterialIcons';
import LinearGradient from 'react-native-linear-gradient';
import { LineChart, BarChart, PieChart } from 'react-native-chart-kit';
import QRCode from 'react-native-qrcode-svg';

// Screen imports
import LoginScreen from './src/screens/LoginScreen';
import RegisterScreen from './src/screens/RegisterScreen';
import DashboardScreen from './src/screens/DashboardScreen';
import PortfolioScreen from './src/screens/PortfolioScreen';
import TradeScreen from './src/screens/TradeScreen';
import HistoryScreen from './src/screens/HistoryScreen';
import ProfileScreen from './src/screens/ProfileScreen';
import SettingsScreen from './src/screens/SettingsScreen';

// Theme configuration (will be dynamically loaded per client)
const theme = {
  primaryColor: '#007AFF',
  secondaryColor: '#5856D6',
  accentColor: '#BF953F',
  backgroundColor: '#F8F9FA',
  cardBackground: '#FFFFFF',
  textPrimary: '#212529',
  textSecondary: '#6C757D',
  goldColor: '#FFD700',
  silverColor: '#C0C0C0',
  platinumColor: '#E5E4E2'
};

const Stack = createStackNavigator();
const Tab = createBottomTabNavigator();

const App = () => {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [tenantConfig, setTenantConfig] = useState(null);
  const [userData, setUserData] = useState(null);

  useEffect(() => {
    initializeApp();
  }, []);

  const initializeApp = async () => {
    try {
      // Load tenant configuration
      await loadTenantConfig();
      
      // Check authentication status
      const token = await AsyncStorage.getItem('auth_token');
      if (token) {
        setIsAuthenticated(true);
      }
      
      // Load user data if authenticated
      if (token) {
        await loadUserData();
      }
      
    } catch (error) {
      console.error('App initialization error:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const loadTenantConfig = async () => {
    try {
      // In a real app, this would fetch from API
      // For demo, using sample configuration
      const config = {
        companyName: 'Demo Gold Platform',
        brand: {
          primaryColor: '#007AFF',
          secondaryColor: '#5856D6',
          accentColor: '#BF953F',
          logoUrl: null
        },
        features: {
          tokens: ['GOLD', 'SILVER', 'PLATINUM'],
          paymentMethods: ['UPI', 'CARD', 'NET_BANKING']
        }
      };
      
      setTenantConfig(config);
      applyBrandConfig(config.brand);
      
    } catch (error) {
      console.error('Error loading tenant config:', error);
    }
  };

  const applyBrandConfig = (brandConfig) => {
    // Apply brand colors dynamically
    // In a real implementation, this would update theme variables
    console.log('Applying brand config:', brandConfig);
  };

  const loadUserData = async () => {
    try {
      // In a real app, this would fetch user data from API
      const user = {
        name: 'Raj Kumar',
        email: 'raj.kumar@example.com',
        totalBalance: 156700,
        avatar: null
      };
      
      setUserData(user);
      
    } catch (error) {
      console.error('Error loading user data:', error);
    }
  };

  const handleLogin = async (credentials) => {
    try {
      // In a real app, this would authenticate with API
      const token = 'demo_token_' + Date.now();
      
      await AsyncStorage.setItem('auth_token', token);
      setIsAuthenticated(true);
      
      await loadUserData();
      
      Alert.alert('Success', 'Login successful!');
      
    } catch (error) {
      console.error('Login error:', error);
      Alert.alert('Error', 'Login failed. Please try again.');
    }
  };

  const handleLogout = async () => {
    try {
      await AsyncStorage.clear();
      setIsAuthenticated(false);
      setUserData(null);
      
      Alert.alert('Success', 'Logged out successfully');
      
    } catch (error) {
      console.error('Logout error:', error);
    }
  };

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={theme.primaryColor} />
        <Text style={styles.loadingText}>Loading...</Text>
      </View>
    );
  }

  if (!isAuthenticated) {
    return (
      <NavigationContainer>
        <Stack.Navigator screenOptions={{ headerShown: false }}>
          <Stack.Screen name="Login" component={LoginScreen} />
          <Stack.Screen name="Register" component={RegisterScreen} />
        </Stack.Navigator>
      </NavigationContainer>
    );
  }

  return (
    <NavigationContainer>
      <Stack.Navigator screenOptions={{ headerShown: false }}>
        <Stack.Screen name="Main">
          {() => (
            <MainTabNavigator 
              userData={userData} 
              onLogout={handleLogout}
              tenantConfig={tenantConfig}
            />
          )}
        </Stack.Screen>
        <Stack.Screen name="Trade" component={TradeScreen} />
        <Stack.Screen name="History" component={HistoryScreen} />
        <Stack.Screen name="Profile" component={ProfileScreen} />
        <Stack.Screen name="Settings" component={SettingsScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
};

// Main Tab Navigator
const MainTabNavigator = ({ userData, onLogout, tenantConfig }) => {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        tabBarIcon: ({ focused, color, size }) => {
          let iconName;

          switch (route.name) {
            case 'Dashboard':
              iconName = 'dashboard';
              break;
            case 'Portfolio':
              iconName = 'account-balance-wallet';
              break;
            case 'Trade':
              iconName = 'trending-up';
              break;
            case 'History':
              iconName = 'receipt';
              break;
            case 'Profile':
              iconName = 'person';
              break;
            default:
              iconName = 'circle';
          }

          return <Icon name={iconName} size={size} color={color} />;
        },
        tabBarActiveTintColor: theme.primaryColor,
        tabBarInactiveTintColor: theme.textSecondary,
        tabBarStyle: {
          backgroundColor: theme.cardBackground,
          borderTopColor: theme.textSecondary + '20'
        },
        headerStyle: {
          backgroundColor: theme.primaryColor
        },
        headerTintColor: 'white',
        headerTitleStyle: {
          fontWeight: 'bold'
        }
      })}
    >
      <Tab.Screen 
        name="Dashboard" 
        options={{ 
          title: tenantConfig?.companyName || 'Dashboard',
          headerRight: () => (
            <TouchableOpacity onPress={onLogout} style={{ marginRight: 20 }}>
              <Icon name="logout" size={24} color="white" />
            </TouchableOpacity>
          )
        }}
      >
        {() => <DashboardScreen userData={userData} tenantConfig={tenantConfig} />}
      </Tab.Screen>
      <Tab.Screen name="Portfolio" component={PortfolioScreen} />
      <Tab.Screen name="Trade" component={TradeScreen} />
      <Tab.Screen name="History" component={HistoryScreen} />
      <Tab.Screen name="Profile" component={ProfileScreen} />
    </Tab.Navigator>
  );
};

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: theme.backgroundColor
  },
  loadingText: {
    marginTop: 16,
    fontSize: 16,
    color: theme.textSecondary
  }
});

export default App;