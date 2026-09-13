import React, { createContext, useContext, useState, useEffect } from 'react';

const AccessibilityContext = createContext(null);

export function AccessibilityProvider({ children }) {
  const [theme, setTheme] = useState(() => localStorage.getItem('ln_theme') || 'dark');
  const [dyslexiaFont, setDyslexiaFont] = useState(() => localStorage.getItem('ln_dyslexia') === 'true');
  const [fontSize, setFontSize] = useState(() => Number(localStorage.getItem('ln_font_size')) || 1);

  // Sync theme
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('ln_theme', theme);
  }, [theme]);

  // Sync dyslexia font
  useEffect(() => {
    if (dyslexiaFont) {
      document.body.classList.add('font-dyslexia');
    } else {
      document.body.classList.remove('font-dyslexia');
    }
    localStorage.setItem('ln_dyslexia', String(dyslexiaFont));
  }, [dyslexiaFont]);

  // Sync font size
  useEffect(() => {
    document.documentElement.style.setProperty('--user-font-scale', String(fontSize));
    localStorage.setItem('ln_font_size', String(fontSize));
  }, [fontSize]);

  const toggleTheme = () => {
    setTheme(prev => {
      if (prev === 'dark') return 'light';
      if (prev === 'light') return 'high-contrast';
      return 'dark';
    });
  };

  const toggleDyslexiaFont = () => {
    setDyslexiaFont(prev => !prev);
  };

  return (
    <AccessibilityContext.Provider value={{
      theme,
      setTheme,
      toggleTheme,
      dyslexiaFont,
      toggleDyslexiaFont,
      fontSize,
      setFontSize
    }}>
      {children}
    </AccessibilityContext.Provider>
  );
}

export function useAccessibility() {
  const context = useContext(AccessibilityContext);
  if (!context) {
    throw new Error('useAccessibility must be used within AccessibilityProvider');
  }
  return context;
}
