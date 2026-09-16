import React, { useState } from 'react';
import { AccessibilityProvider } from './context/AccessibilityContext';
import { AudioPlayerProvider } from './context/AudioPlayerContext';
import Navbar from './components/Navbar';
import Hero from './components/Hero';
import AudioSimulator from './components/AudioSimulator';
import FeaturesBento from './components/FeaturesBento';
import ArchitectureComparison from './components/ArchitectureComparison';
import VoiceEngineSection from './components/VoiceEngineSection';
import EarlyStageSection from './components/EarlyStageSection';
import RoadmapSection from './components/RoadmapSection';
import DownloadSection from './components/DownloadSection';
import Footer from './components/Footer';
import IdeaProposalModal from './components/IdeaProposalModal';
import './styles/app.css';

export default function App() {
  const [proposalModalOpen, setProposalModalOpen] = useState(false);

  return (
    <AccessibilityProvider>
      <AudioPlayerProvider>
        <div style={{ position: 'relative', overflow: 'hidden' }}>
          {/* Ambient Glows */}
          <div className="ambient-glow-top" />
          <div className="ambient-glow-mid" />

          {/* Navigation Bar */}
          <Navbar />

          {/* Main Sections */}
          <main>
            <Hero />
            <AudioSimulator />
            <FeaturesBento />
            <ArchitectureComparison />
            <VoiceEngineSection />
            <EarlyStageSection onOpenProposalModal={() => setProposalModalOpen(true)} />
            <RoadmapSection onOpenProposalModal={() => setProposalModalOpen(true)} />
            <DownloadSection />
          </main>

          {/* Footer */}
          <Footer />

          {/* Idea Proposal Modal */}
          <IdeaProposalModal
            isOpen={proposalModalOpen}
            onClose={() => setProposalModalOpen(false)}
          />
        </div>
      </AudioPlayerProvider>
    </AccessibilityProvider>
  );
}
