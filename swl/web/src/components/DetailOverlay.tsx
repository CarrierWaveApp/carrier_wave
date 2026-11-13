import { useEffect, useCallback, type ReactNode } from 'react';
import { tokens } from '../styles/tokens';

interface DetailOverlayProps {
  isOpen: boolean;
  onClose: () => void;
  children: ReactNode;
}

export function DetailOverlay({ isOpen, onClose, children }: DetailOverlayProps) {
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    },
    [onClose],
  );

  useEffect(() => {
    if (isOpen) {
      document.addEventListener('keydown', handleKeyDown);
      document.body.style.overflow = 'hidden';
    }
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      document.body.style.overflow = '';
    };
  }, [isOpen, handleKeyDown]);

  if (!isOpen) return null;

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 200,
        display: 'flex',
        alignItems: 'flex-end',
        justifyContent: 'center',
      }}
    >
      {/* Backdrop */}
      <div
        onClick={onClose}
        style={{
          position: 'absolute',
          inset: 0,
          background: 'rgba(0,0,0,0.6)',
          backdropFilter: 'blur(4px)',
          WebkitBackdropFilter: 'blur(4px)',
          animation: 'overlayFadeIn 0.2s ease-out',
        }}
      />

      {/* Panel */}
      <div
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: '720px',
          maxHeight: '85vh',
          overflowY: 'auto',
          background: tokens.color.bg,
          borderRadius: `${tokens.radius.lg} ${tokens.radius.lg} 0 0`,
          boxShadow: '0 -4px 32px rgba(0,0,0,0.4)',
          animation: 'overlaySlideUp 0.25s ease-out',
          padding: '1.5rem',
        }}
      >
        {/* Close button */}
        <button
          onClick={onClose}
          style={{
            position: 'absolute',
            top: '1rem',
            right: '1rem',
            background: tokens.color.surface,
            border: 'none',
            borderRadius: '50%',
            width: 32,
            height: 32,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: 'pointer',
            color: tokens.color.textSecondary,
            fontSize: '1.125rem',
            lineHeight: 1,
          }}
          title="Close"
        >
          ✕
        </button>

        {children}
      </div>
    </div>
  );
}
